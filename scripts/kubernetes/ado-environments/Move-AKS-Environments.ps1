# This script requires PowerShell 7, Azure CLI and kubectl installed.

Param(
  [Parameter(Mandatory = $true)]
  $AccessToken, # Access token that is used to call Azure DevOps REST API
  [Parameter(Mandatory = $true)]
  $AzureDevOpsURL, # URL to Azure DevOps project
  [Parameter(Mandatory = $true)]
  $SourceEnvironmentName, # Name of the Azure DevOps Environment to migrate resources from
  [Parameter(Mandatory = $true)]
  $TargetEnvironmentName, # Name of the Azure DevOps Environment to migrate resources to. If it doesn't exist, it will be created first.
  [Parameter(Mandatory = $false)]
  $AzureDevOpsApiVersion = "api-version=6.0-preview.1", # (Optional) Version of Azure DevOps REST API.
  [Parameter(Mandatory = $false)]
  $TargetEnvironmentDescription, # (Optional) For creation of new environment you can provide desired description that will be added upon creation.
  [Parameter(Mandatory = $false)]
  $TargetClusterName = $null, # (Optional) If cluster name isn't provided, source cluster name will be used upon migration
  [Parameter(Mandatory = $false)]
  $TargetClusterResourceGroup, # (Optional) If new cluster will be used for resource, Azure resource group that the cluster is deployed to must be provided.
  [Parameter(Mandatory = $false)]
  $SubscriptionId, # (Optional) If new cluster will be used for resource, Azure subscription ID must be provided to generate a service connection for the new cluster.
  [Parameter(Mandatory = $false)]
  $TenantId # (Optional) If new cluster will be used for resource, Azure AD tenant ID must be provided to generate a service connection for the new cluster.
  )

$global:DebugPreference = "Continue";

function Get-SourceEnvironment()
{
    $sourceEnvironmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$SourceEnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about Azure DevOps Environment: $sourceEnvironmentUrl. Calling..."
    $sourceEnvironmentResult = (Invoke-RestMethod -Uri $sourceEnvironmentUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value
    
    if($sourceEnvironmentResult.count -eq 0)
    {
        Write-Debug "No source environment with name $SourceEnvironmentName found! Exiting..."
        exit 1
    }

    $sourceEnvironmentResourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$($sourceEnvironmentResult.id)?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "URL to retrieve all resources connected to the Azure DevOps Environment: $sourceEnvironmentResourcesUrl."
    $sourceEnvironmentResourcesResult = (Invoke-RestMethod -Uri $sourceEnvironmentResourcesUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30)

    if($sourceEnvironmentResourcesResult.resources.count -eq 0)
    {
        Write-Debug "No resources found to migrate from Azure DevOps Environment: $SourceEnvironmentName. Exiting..."
        exit 1
    }

    return $sourceEnvironmentResourcesResult
}

function Get-TargetEnvironmentId()
{
    $targetEnvironmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$TargetEnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about Azure DevOps Environment: $targetEnvironmentUrl. Calling..."
    $targetEnvironmentResult = (Invoke-RestMethod -Uri $targetEnvironmentUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value

    # If target environment doesn't exist - create one
    if($targetEnvironmentResult.count -eq 0)
    {
        Write-Debug "Target Azure DevOps Environment doesn't exist - creating..."
        $targetEnvironmentObject = @{
            name = $TargetEnvironmentName;
            description = $TargetEnvironmentDescription;
        }
        $targetEnvironmentObject = $targetEnvironmentObject | ConvertTo-Json
        $targetEnvironment = Invoke-RestMethod -Uri $targetEnvironmentUrl -Method POST -Headers $authHeader -Body $targetEnvironmentObject -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30
        
        return $targetEnvironment.id
    }

    Write-Debug "Target environment ID is: $($targetEnvironmentResult.id)"
    return $targetEnvironmentResult.id
}

function New-SvcConnection($resourceNamespace)
{    
    Write-Debug "Generating service connection for new resource..."   

    $subscriptionName = ((az account subscription show --subscription-id $SubscriptionId) | ConvertFrom-Json).DisplayName
    Write-Debug "Azure subscription name is $subscriptionName"

    $targetClusterInfo = az aks show --name $TargetClusterName --resource-group $TargetClusterResourceGroup | ConvertFrom-Json
    $targetClusterUrl = [uri]"https://$($targetClusterInfo.fqdn)"
    Write-Debug "Target cluster URL is: $($targetClusterUrl.AbsoluteUri)"

    $svcConnectionName = "$TargetEnvironmentName-$TargetClusterName-$resourceNamespace"
    $existingSvcConnectionId = Get-SvcConnectionIfExists -endpointName $svcConnectionName
    
    if($null -ne $existingSvcConnectionId)
    {
        Write-Debug "Service connection with name $svcConnectionName already exists - returning service connection id: $existingSvcConnectionId..."
        return $existingSvcConnectionId
    }

    $adoProjectName = $AzureDevOpsURL.TrimEnd('/').Split('/')[-1]
    $adoOrgUrl = [uri]($AzureDevOpsURL | Split-Path -Parent).Replace('\','/')

    Write-Debug "Azure DevOps project name: $adoProjectName. Azure DevOps organization url: $adoOrgUrl"

    $adoProjectIdUrl = [uri]"$adoOrgUrl/_apis/projects?$AzureDevOpsApiVersion" 
    Write-Debug "URL to get Azure DevOps project id: $adoProjectIdUrl. Calling..."
    $adoProjectIdResult = (Invoke-RestMethod -Uri $adoProjectIdUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value | Where-Object {$_.name -eq $adoProjectName}
    
    kubectl config set-context $targetClusterInfo.name
    $ns = kubectl get namespace $resourceNamespace
    $createNamespace = "false"
    
    if($ns.Count -eq 0)
    {
        $createNamespace = "true"
    }

    Write-Debug "Replacing placeholders for service connection template"
	$svcConnectionTemplatePath = "$PSScriptRoot/kube-svc-connection-template.json"
    $svcConnectionObject = (Get-Content $svcConnectionTemplatePath) `
	|  ForEach-Object `
		{ `
			$_  -replace "\[SubscriptionId\]", $SubscriptionId `
				-replace "\[SubscriptionName\]", $subscriptionName `
				-replace "\[ClusterId\]", $targetClusterInfo.id `
                -replace "\[Namespace\]", $resourceNamespace `
                -replace "\[CreateNamespace\]", $createNamespace `
				-replace "\[ConnectionName\]", $svcConnectionName `
				-replace "\[ClusterUrl\]", $targetClusterUrl `
                -replace "\[TenantId\]", $TenantId `
				-replace "\[ProjectId\]", $adoProjectIdResult.id `
				-replace "\[ProjectName\]", $adoProjectName `
		}
    Write-Debug "$svcConnectionObject"
    $svcConnectionUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/serviceendpoint/endpoints?$AzureDevOpsApiVersion"
    Write-Debug "URL to create service connection for Kubernetes resource: $svcConnectionUrl. Calling..."
    $svcConnectionResult = Invoke-RestMethod -Uri $svcConnectionUrl -Method POST -Body $svcConnectionObject -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30

    Write-Debug "Service connection $svcConnectionName with id $($svcConnectionResult.id) for Kubernetes resource successfully created!"
    return $svcConnectionResult.id
}

function Get-SvcConnectionIfExists($endpointName)
{
    $getSvcConnectionUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/serviceendpoint/endpoints?endpointNames=$endpointName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get service connection for Kubernetes resource: $getSvcConnectionUrl. Calling..."
    $getSvcConnectionResult = Invoke-RestMethod -Uri $getSvcConnectionUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30

    if($getSvcConnectionResult.count -eq 0)
    {
        return $null
    }

    return $getSvcConnectionResult.value.id
}

function Test-ResourceExists($environmentId, $resourceName)
{
    $resourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$($environmentId)?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "Checking if resource $resourceName exists in Azure DevOps environment with id: $environmentId. Calling url: $resourcesUrl"
    $resourcesResult = (Invoke-RestMethod -Uri $resourcesUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).resources | Where-Object {$_.name -eq $resourceName}

    if($resourcesResult.count -eq 0)
    {        
        return $false
    }

    return $true
}

$user = ""
$base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $AccessToken)))
$authHeader = @{ Authorization = "Basic $base64Token" }

az login

$sourceEnvironment = Get-SourceEnvironment
$targetEnvironmentId = Get-TargetEnvironmentId
$addResourcesUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments/$($targetEnvironmentId)/providers/kubernetes?$AzureDevOpsApiVersion"

foreach($resource in $sourceEnvironment.resources)
{   
    Write-Debug "Check if Kubernetes resource already exists in target environment..."

    if(Test-ResourceExists -environmentId $targetEnvironmentId -resourceName $resource.name)
    {
        Write-Debug "Resource $($resource.name) already exists in $TargetEnvironmentName! Skipping..."
        continue
    }

    $kubernetesResourceUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments/$($sourceEnvironment.id)/providers/kubernetes/$($resource.id)?$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about Kubernetes resource: $kubernetesResourceUrl. Calling..."
    $kubeResourceResult = Invoke-RestMethod -Uri $kubernetesResourceUrl -Method GET -Headers $authHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30
    
    $svcConnectionId = $kubeResourceResult.serviceEndpointId
    $resourceCluster = $kubeResourceResult.clusterName

    if($null -ne $TargetClusterName)
    {
        $resourceCluster = $TargetClusterName
        $svcConnectionId = New-SvcConnection -resourceNamespace $kubeResourceResult.namespace
    }

    $requestObject = @{
        clusterName = $resourceCluster;
        name = $kubeResourceResult.name;
        namespace = $kubeResourceResult.namespace;
        tags = $kubeResourceResult.tags;
        serviceEndpointId = $svcConnectionId;
    } | ConvertTo-Json

    Write-Debug "URL to create Kubernetes resources: $addResourcesUrl. Calling..."
    Invoke-RestMethod -Uri $addResourcesUrl -Method POST -Headers $authHeader -Body $requestObject -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30
}

Write-Debug "Success! All resources have been migrated to $TargetEnvironmentName!"