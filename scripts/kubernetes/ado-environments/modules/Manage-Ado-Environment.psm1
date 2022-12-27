$global:DebugPreference = "Continue";

function New-ADO-Environment()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName,

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )   

    $environmentObject = @{
        name = $EnvironmentName;
    }

    $environmentObject = $environmentObject | ConvertTo-Json
    $environmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$EnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to create Azure DevOps Environment: $environmentUrl. Calling..."

    $adoEnvironment = Invoke-RestMethod -Uri $environmentUrl -Method POST -Headers $AuthHeader -Body $environmentObject -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30

    Write-Debug "Azure DevOps Environment $EnvironmentName created!"

    return $adoEnvironment
}

function Get-ADO-Environment()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName,

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0", # (Optional) Version of Azure DevOps REST API.
        
        [switch]$CreateIfNotExists
    )

    $environmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$EnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about Azure DevOps Environment: $environmentUrl. Calling..."
    $adoEnvironment = (Invoke-RestMethod -Uri $environmentUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value

    if($adoEnvironment.count -eq 0 -and -not $CreateIfNotExists)
    {
        Write-Debug "Azure DevOps Environment $EnvironmentName doesn't exist! Please create Azure DevOps Environment or run the script with CreateIfNotExists switch"
        exit 1
    }
    elseif ($adoEnvironment.count -eq 0 -and $CreateIfNotExists) 
    {
        Write-Debug "Azure DevOps Environment $EnvironmentName doesn't exist! Creating..."

        $adoEnvironment = New-ADO-Environment -AzureDevOpsURL $AzureDevOpsUrl -EnvironmentName $EnvironmentName -AuthHeader $AuthHeader
    }

     
    return $adoEnvironment
}

function New-ADO-Environment-Resource {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
        
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionId,

        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName,

        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoResourcesUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments/$EnvironmentId/providers/kubernetes?$AzureDevOpsApiVersion"
    Write-Debug "Check if Kubernetes resource already exists in Azure DevOps environment with ID $EnvironmentId..."

    if(Test-ADO-Resource-Exists -AzureDevOpsUrl $AzureDevOpsUrl -EnvironmentId $EnvironmentId -ResourceName $KubernetesResourceNamespace -AuthHeader $AuthHeader)
    {
        Write-Debug "Resource $KubernetesResourceNamespace already exists in Azure DevOps Environment with ID! Skipping..."
        continue
    }

    $adoResourceRequestObject = @{
        clusterName = $KubernetesClusterName;
        name = $KubernetesResourceNamespace;
        namespace = $KubernetesResourceNamespace;
        tags = @();
        serviceEndpointId = $ServiceConnectionId;
    } | ConvertTo-Json

    Write-Debug "Creating resource with these details: $adoResourceRequestObject"
    Write-Debug "URL to create Kubernetes resources: $adoResourcesUrl. Calling..."
    Invoke-RestMethod -Uri $adoResourcesUrl -Method POST -Headers $AuthHeader -Body $adoResourceRequestObject -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30


    Write-Debug "Success! Resource $KubernetesResourceNamespace has been created!"
}

function Get-ADO-Environment-Resources
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId,

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoEnvironmentResourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$EnvironmentId?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "URL to retrieve all resources connected to the Azure DevOps Environment: $adoEnvironmentResourcesUrl."
    $adoEnvironmentResources = (Invoke-RestMethod -Uri $adoEnvironmentResourcesUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30)

    if($adoEnvironmentResources.resources.count -eq 0)
    {
        Write-Debug "No resources found for Azure DevOps Environment with ID $EnvironmentId. Exiting..."
        exit 1
    }

    return $adoEnvironmentResources
}

# This function will check if service connection with current name already exists in Azure DevOps. If it does, it will be returned.
function Get-SvcConnection
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EndpointName,

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $svcConnectionUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/serviceendpoint/endpoints?endpointNames=$EndpointName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get service connection for Kubernetes resource: $svcConnectionUrl. Calling..."
    $svcConnection = Invoke-RestMethod -Uri $svcConnectionUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30

    if($svcConnection.count -eq 0)
    {
        Write-Debug "Service connection $EndpointName doesn't exist!"
        return $null
    }

    return $svcConnection
}

# This function will generate a new service connection in order to create new Kubernetes resource in target environment.
# If service connection for this resource already exists, the function will return it's ID.
function New-Service-Connection
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name

        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName,

        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName,

        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory=$true,
            ParameterSetName = 'AKSProvider')]
        [string]$SubscriptionId,
        
        [Parameter(Mandatory=$true,
            ParameterSetName = 'GenericProvider')]
        [string]$KubernetesClusterUrl,

        [Parameter(Mandatory = $true,
            ParameterSetName = 'GenericProvider')]
        [switch]$UseGenericProvider,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0", # (Optional) Version of Azure DevOps REST API.
        
        [Parameter(Mandatory = $false,
            ParameterSetName = 'GenericProvider')]
        [boolean]$AcceptUntrustedCertificates = $false        
    )

    $svcConnectionName = "$EnvironmentName-$KubernetesClusterName-$KubernetesResourceNamespace"

    # Verify that service connection for current resource and Kubernetes cluster doesn't already exist. If it does, re-use it.
    $existingSvcConnectionId = Get-SvcConnection -AzureDevOpsUrl $AzureDevOpsUrl -EndpointName $svcConnectionName -AuthHeader $AuthHeader
    
    if($null -ne $existingSvcConnectionId)
    {
        Write-Debug "Service connection with name $svcConnectionName already exists - returning service connection id: $existingSvcConnectionId..."
        return $existingSvcConnectionId
    }

    $adoProjectName = $AzureDevOpsUrl.TrimEnd('/').Split('/')[-1]
    $adoOrgUrl = [uri]($AzureDevOpsUrl | Split-Path -Parent).Replace('\','/')
    Write-Debug "Azure DevOps project name: $adoProjectName. Azure DevOps organization url: $adoOrgUrl"

    $adoProjectIdUrl = [uri]"$adoOrgUrl/_apis/projects?$AzureDevOpsApiVersion" 
    Write-Debug "URL to get Azure DevOps project id: $adoProjectIdUrl. Calling..."
    
    $adoProjectIdResult = (Invoke-RestMethod -Uri $adoProjectIdUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value | Where-Object {$_.name -eq $adoProjectName}
    
    kubectl config set-context $KubernetesClusterName | Out-Null
    $kubeNamespace = kubectl get namespace $KubernetesResourceNamespace
    
    if($kubeNamespace.Count -eq 0)
    {
        Write-Debug "Kubernetes Namespace $KubernetesResourceNamespace doesn't exist - creating..."
        kubectl create namespace $KubernetesResourceNamespace
    }

    if($UseGenericProvider)
    {
        $guid = (New-Guid).ToString().substring(0,6) # account names that are generated by Azure DevOps use 5 characters - use 6 to avoid potential duplication
        $svcAccountName = "azdev-sa-$guid"

        Write-Debug "Creating Service Account $svcAccountName..."
        New-Kubernetes-ServiceAccount -ServiceAccountName $svcAccountName -KubernetesResourceNamespace $KubernetesResourceNamespace
        
        
        Write-Debug "Getting authorization information for $svcAccountName..."
        $svcAccountSecret = kubectl get secret -n $KubernetesResourceNamespace $("$svcAccountName-token") -o json | ConvertFrom-Json

        Write-Debug "Generating Generic Kubernetes Service Connection Object..."
        $svcConnectionObject = New-Generic-Kubernetes-Service-Connection-Object -KubernetesClusterUrl $KubernetesClusterUrl -ServiceAccountName $svcAccountName -ServiceAccountCertificate $svcAccountSecret.data.{ca.crt} -ServiceAccountApiToken $svcAccountSecret.data.token -ServiceConnectionName $svcConnectionName -ADOProjectId $adoProjectIdResult.id -ADOProjectName $adoProjectName -AcceptUntrustedCertificates $AcceptUntrustedCertificates
    }
    else 
    {
        Write-Debug "Generating AKS Service Connection Object..."
        $svcConnectionObject = New-AKS-Service-Connection-Object -KubernetesClusterName $KubernetesClusterName -SubscriptionId $SubscriptionId -ServiceConnectionName $svcConnectionName -ADOProjectId $adoProjectIdResult.id -ADOProjectName $adoProjectName
    }

    $svcConnectionUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/serviceendpoint/endpoints?$AzureDevOpsApiVersion"

    Write-Debug "URL to create service connection for Kubernetes resource: $svcConnectionUrl. Calling..."
    $svcConnectionResult = Invoke-RestMethod -Uri $svcConnectionUrl -Method POST -Body $svcConnectionObject -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30

    Write-Debug "Service connection $svcConnectionName with id $($svcConnectionResult.id) for Kubernetes resource successfully created!"
    return $svcConnectionResult
}

function New-AKS-Service-Connection-Object 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName,

        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId,

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionName,

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectId,

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectName,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
        
    )

    $kubernetesCluster = az aks list | ConvertFrom-Json | Where-Object { $_.name -eq $KubernetesClusterName }
    $kubernetesClusterUrl = [uri]"https://$($kubernetesCluster.fqdn)"
    Write-Debug "Kubernetes cluster URL is: $($kubernetesClusterUrl.AbsoluteUri)"

    Write-Debug "Generating service connection..."   

    # First, gather the information that's required by Azure DevOps REST API in order to create a new service connection for Kubernetes
    $subscriptionName = ((az account subscription show --subscription-id $SubscriptionId) | ConvertFrom-Json).DisplayName
    Write-Debug "Azure subscription name is $subscriptionName"

    # Populate JSON object based on the template with retrieved values for new service connection
    Write-Debug "Replacing placeholders for service connection template"
	$svcConnectionTemplatePath = "$PSScriptRoot/../templates/aks-svc-connection-template.json"
    $serviceConnectionObject = (Get-Content $svcConnectionTemplatePath) `
	|  ForEach-Object `
		{ `
			$_  -replace "\[SubscriptionId\]", $SubscriptionId `
				-replace "\[SubscriptionName\]", $subscriptionName `
				-replace "\[ClusterId\]", $kubernetesCluster.id `
                -replace "\[Namespace\]", $KubernetesResourceNamespace `
				-replace "\[ConnectionName\]", $ServiceConnectionName `
				-replace "\[ClusterUrl\]", $kubernetesClusterUrl `
                -replace "\[TenantId\]", $kubernetesCluster.identity.tenantId `
				-replace "\[ProjectId\]", $ADOProjectId `
				-replace "\[ProjectName\]", $ADOProjectName `
		}
    
        Write-Debug "AKS Service Connection object $ServiceConnectionName created!"

    return $serviceConnectionObject
}

function New-Generic-Kubernetes-Service-Connection-Object 
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$KubernetesClusterUrl,

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountName, 
        
        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountCertificate,

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountApiToken,

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionName,

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectId,

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectName,

        [Parameter(Mandatory = $false)]
        [boolean]$AcceptUntrustedCertificates = $false,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    Write-Debug "Generating service connection..."   

    # Populate JSON object based on the template with retrieved values for new service connection
    Write-Debug "Replacing placeholders for service connection template"
	$svcConnectionTemplatePath = "$PSScriptRoot/../templates/generic-k8s-svc-connection-template.json"
    $serviceConnectionObject = (Get-Content $svcConnectionTemplatePath) `
	|  ForEach-Object `
		{ `
			$_  -replace "\[AcceptUntrustedCerts\]", $AcceptUntrustedCertificates.ToString().ToLower() `
                -replace "\[ConnectionName\]", $ServiceConnectionName `
                -replace "\[ClusterUrl\]", $KubernetesClusterUrl `
				-replace "\[ApiToken\]", $ServiceAccountApiToken `
                -replace "\[ServiceAccountCertificate\]", $ServiceAccountCertificate `
				-replace "\[ProjectId\]", $ADOProjectId `
				-replace "\[ProjectName\]", $ADOProjectName `
		}
    
        Write-Debug "Generic Kubernetes Service Connection object $ServiceConnectionName created!"

    return $serviceConnectionObject
    
}

function New-Kubernetes-ServiceAccount
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountName
    )

    $tempOutputPath = [System.IO.Path]::GetTempPath()

    Write-Debug "Replacing placeholders for ServiceAccount template"
    (Get-Content "$PSScriptRoot/../templates/serviceaccount.yml") `
    |  ForEach-Object `
        { `
            $_  -replace "\[ServiceAccountName\]", $ServiceAccountName `
                -replace "\[Namespace\]", $KubernetesResourceNamespace `
        } `
    | Set-Content "$tempOutputPath/serviceaccount.yml" -Encoding UTF8

    Write-Debug "Replacing placeholders for service account Secret template"
    (Get-Content "$PSScriptRoot/../templates/secret.yml") `
    |  ForEach-Object `
        { `
            $_  -replace "\[ServiceAccountName\]", $ServiceAccountName `
                -replace "\[Namespace\]", $KubernetesResourceNamespace `
        } `
    | Set-Content "$tempOutputPath/secret.yml" -Encoding UTF8

    Write-Debug "Replacing placeholders for service account RoleBinding template"
    (Get-Content "$PSScriptRoot/../templates/rolebinding.yml") `
    |  ForEach-Object `
        { `
            $_  -replace "\[ServiceAccountName\]", $ServiceAccountName `
                -replace "\[Namespace\]", $KubernetesResourceNamespace `
        } `
    | Set-Content "$tempOutputPath/rolebinding.yml" -Encoding UTF8

    Write-Debug "Checking if Kubernetes Namespace exists..."
    $kubernetesNamespace = kubectl get namespace $KubernetesResourceNamespace

    if($kubernetesNamespace.Count -eq 0)
    {
        Write-Debug "Kubernetes Namespace $KubernetesResourceNamespace doesn't exist - creating..."
        kubectl create namespace $KubernetesResourceNamespace
    }

    Write-Debug "Creating respective Kubernetes resources in $KubernetesResourceNamespace namespace..."

    kubectl apply -f "$tempOutputPath/serviceaccount.yml"
    kubectl apply -f "$tempOutputPath/secret.yml"
    kubectl apply -f "$tempOutputPath/rolebinding.yml"

    Write-Debug "ServiceAccount $ServiceAccountName with Secret and RoleBinding created in $KubernetesResourceNamespace!"
}

# This function checks if the AKS resource already exists in respective Azure DevOps Environment
function Test-ADO-Resource-Exists
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId,

		[Parameter(Mandatory=$true)]
        [string]$ResourceName,

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader,

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoResourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$($EnvironmentId)?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "Checking if resource $ResourceName exists in Azure DevOps environment with id: $EnvironmentId. Calling url: $adoResourcesUrl"
    $adoResource = (Invoke-RestMethod -Uri $adoResourcesUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).resources | Where-Object {$_.name -eq $ResourceName}

    if($adoResource.count -eq 0)
    {
        Write-Debug "Resource $ResourceName doesn't exist in Azure DevOps Environment with ID $EnvironmentId"
        return $false
    }

    return $true
}

Export-ModuleMember Get-ADO-Environment, New-Service-Connection, New-ADO-Environment-Resource