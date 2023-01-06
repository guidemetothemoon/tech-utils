# This PowerShell Module contains functions that can help you manage different tasks related to Azure DevOps Environments, 
# like for example, create a new Azure DevOps Environment, create a new Azure DevOps Environment Kubernetes Resource with respective Service Connection, etc.

# You can start using the module once you import it with Import-Module <path_to_psm1_file>, f.ex.: Import-Module "./modules/Manage-Ado-Environment.psm1"

$global:DebugPreference = "Continue";
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Create new Azure DevOps Environment with the provided name.
function New-ADO-Environment()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName, # Azure DevOps Environment name

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        $EnvironmentDescription, # (Optional) For creation of new environment you can provide desired description that will be added upon creation.

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )   

    $environmentObject = @{
        name = $EnvironmentName;
        description = $EnvironmentDescription;
    }

    $environmentObject = $environmentObject | ConvertTo-Json
    $environmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$EnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to create Azure DevOps Environment: $environmentUrl. Calling..."
    $adoEnvironment = Invoke-RestMethod -Uri $environmentUrl -Method POST -Headers $AuthHeader -Body $environmentObject -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30
    
    Write-Debug "Azure DevOps Environment $EnvironmentName created!"

    return $adoEnvironment
}

# Get Azure DevOps Environment information based on the name. Create Azure DevOps Environment if it doesn't exist, if $CreateIfNotExists switch is provided.
function Get-ADO-Environment()
{
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName, # Azure DevOps Environment name

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0", # (Optional) Version of Azure DevOps REST API.
        
        [Parameter(Mandatory = $false,
            ParameterSetName = 'CreateEnvironment')]
        $EnvironmentDescription, # (Optional) For creation of new environment you can provide desired description that will be added upon creation.
        
        [Parameter(ParameterSetName = 'CreateEnvironment')]
        [switch]$CreateIfNotExists # If provided, an Azure DevOps Environment with provided name will be created in case it doesn't exist from before.
    )

    $environmentUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments?name=$EnvironmentName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about Azure DevOps Environment: $environmentUrl. Calling..."
    $adoEnvironment = (Invoke-RestMethod -Uri $environmentUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value
    
    if(-not $adoEnvironment -and -not $CreateIfNotExists)
    {
        Write-Error "Azure DevOps Environment $EnvironmentName doesn't exist! Please create Azure DevOps Environment or run the script with CreateIfNotExists switch"
        exit 1
    }
    elseif (-not $adoEnvironment -and $CreateIfNotExists) 
    {
        Write-Debug "Azure DevOps Environment $EnvironmentName doesn't exist! Creating..."
        $adoEnvironment = New-ADO-Environment -AzureDevOpsURL $AzureDevOpsUrl -EnvironmentName $EnvironmentName -AuthHeader $AuthHeader -EnvironmentDescription $EnvironmentDescription
    }
     
    return $adoEnvironment
}

# Create new Azure DevOps Environment Kubernetes Resource, either as an AKS Resource or a Generic Kubernetes Provider Resource, based on provided parameters.
function New-ADO-Environment-Kubernetes-Resource {
    Param
    (
        [Parameter(Mandatory = $true)]
        [string]$AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
        
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId, # Azure DevOps Environment ID where Resource will be created.

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionId, # ID of the Azure DevOps Kubernetes service connection that the Resource will use.

        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName, # Name of the Kubernetes cluster that the Resource will be deployed to.

        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoResourcesUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments/$EnvironmentId/providers/kubernetes?$AzureDevOpsApiVersion"
    Write-Debug "Check if Kubernetes resource already exists in Azure DevOps environment with ID $EnvironmentId..."

    if(Test-ADO-Kubernetes-Resource-Exists -AzureDevOpsUrl $AzureDevOpsUrl -EnvironmentId $EnvironmentId -ResourceName $KubernetesResourceNamespace -AuthHeader $AuthHeader)
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

# Get information about existing Resources for the provided Azure DevOps Environment ID.
function Get-ADO-Environment-Resources
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId, # ID of the Azure DevOps Environment to retrieve Resources for.

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoEnvironmentResourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$($EnvironmentId)?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "URL to retrieve all resources connected to the Azure DevOps Environment: $adoEnvironmentResourcesUrl."
    $adoEnvironmentResources = (Invoke-RestMethod -Uri $adoEnvironmentResourcesUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30)

    if(-not $adoEnvironmentResources.resources)
    {
        Write-Debug "No resources found for Azure DevOps Environment with ID $EnvironmentId. Exiting..."
        return $null
    }

    return $adoEnvironmentResources
}

# Get information about a single Azure DevOps Environment Kubernetes Resource based on Resource ID
function Get-ADO-Environment-Kubernetes-Resource
{
    param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId, # ID of the Azure DevOps Environment to retrieve Resources for.

        [Parameter(Mandatory=$true)]
        [string]$ResourceId, # ID of the Azure DevOps Environment Resource.

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoEnvironmentResourceUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/distributedtask/environments/$EnvironmentId/providers/kubernetes/$($ResourceId)?$AzureDevOpsApiVersion"
    Write-Debug "URL to get details about ADO Environment Kubernetes Resource: $adoEnvironmentResourceUrl. Calling..."
    $adoEnvironmentResource = Invoke-RestMethod -Uri $adoEnvironmentResourceUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30
    
    if(-not $adoEnvironmentResource)
    {
        Write-Debug "No Azure DevOps Kubernetes Resource with ID $ResourceId found in Azure DevOps Environment with ID $EnvironmentId!"
        return $null
    }
    
    return $adoEnvironmentResource
}

# This function will check if service connection with current name already exists in Azure DevOps and return it, if it exists.
function Get-SvcConnection
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionName, # Service Connection name to check

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $svcConnectionUrl = [uri]"$($AzureDevOpsUrl.Trim("/"))/_apis/serviceendpoint/endpoints?endpointNames=$ServiceConnectionName&$AzureDevOpsApiVersion"
    Write-Debug "URL to get service connection for Kubernetes resource: $svcConnectionUrl. Calling..."
    $svcConnection = (Invoke-RestMethod -Uri $svcConnectionUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value

    if(-not $svcConnection)
    {
        Write-Debug "Service connection $ServiceConnectionName doesn't exist!"
        return $null
    }

    return $svcConnection
}

# This function will generate a new Azure DevOps Kubernetes service connection that's required in order to create new Kubernetes resource in an Azure DevOps Environment.
# If service connection for the resource already exists, the function will return it's ID.
function New-Service-Connection
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name

        [Parameter(Mandatory=$true)]
        [string]$EnvironmentName, # Azure DevOps Environment name

        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName, # Kubernetes Cluster name that Resource is deployed to

        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory=$false,
            ParameterSetName = 'AKSProvider')]
        [string]$SubscriptionId, # Azure subscription ID which is required to create an AKS Resource
        
        [Parameter(Mandatory=$false,
            ParameterSetName = 'GenericProvider')]
        [string]$KubernetesClusterUrl, # Kubernetes cluster server AbsoluteUri (format: https://<kubernetes_cluster_url>) which is required to create a Generic Kubernetes Resource

        [Parameter(Mandatory = $false,
            ParameterSetName = 'GenericProvider')]
        [switch]$UseGenericProvider, # When provided, an Azure DevOps Environment Generic Kubernetes Resource will be created

        [Parameter(Mandatory = $false,
            ParameterSetName = 'GenericProvider')]
        [boolean]$AcceptUntrustedCertificates = $false, # Applicable for Generic Kubernetes Resource. Set to true if Kubernetes cluster uses default self-signed TLS certificate (untrusted by default). Defaults to FALSE.

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.       
    )

    $svcConnectionName = "$EnvironmentName-$KubernetesClusterName-$KubernetesResourceNamespace"

    # Verify that service connection for current resource and Kubernetes cluster doesn't already exist. If it does, re-use it.
    $existingSvcConnection = Get-SvcConnection -AzureDevOpsUrl $AzureDevOpsUrl -ServiceConnectionName $svcConnectionName -AuthHeader $AuthHeader
    
    if($existingSvcConnection)
    {
        Write-Debug "Service connection with name $svcConnectionName already exists - returning service connection id: $existingSvcConnection..."
        return $existingSvcConnection
    }

    $adoProjectName = $AzureDevOpsUrl.TrimEnd('/').Split('/')[-1]
    $adoOrgUrl = [uri]($AzureDevOpsUrl | Split-Path -Parent).Replace('\','/')
    Write-Debug "Azure DevOps project name: $adoProjectName. Azure DevOps organization url: $adoOrgUrl"

    $adoProjectIdUrl = [uri]"$adoOrgUrl/_apis/projects?$AzureDevOpsApiVersion" 
    Write-Debug "URL to get Azure DevOps project id: $adoProjectIdUrl. Calling..."
    
    $adoProjectIdResult = (Invoke-RestMethod -Uri $adoProjectIdUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).value | Where-Object {$_.name -eq $adoProjectName}
    
    kubectl config use-context $KubernetesClusterName | Out-Null
    
    if($LASTEXITCODE -ne 0)
    {
        Write-Error "Can't connect to Kubernetes cluster! Please check that your connection is properly set up."
        exit 1
    }

    $kubeNamespace = kubectl get namespace $KubernetesResourceNamespace --ignore-not-found=true
    
    if(-not $kubeNamespace)
    {
        Write-Debug "Kubernetes Namespace $KubernetesResourceNamespace doesn't exist - creating..."
        kubectl create namespace $KubernetesResourceNamespace | Out-Null
    }

    if($UseGenericProvider)
    {
        $guid = (New-Guid).ToString().substring(0,6) # account names that are generated by Azure DevOps use 5 random characters - use 6 to avoid potential duplication
        $svcAccountName = "azdev-sa-$guid"

        Write-Debug "Creating Service Account $svcAccountName..."
        New-Kubernetes-ServiceAccount -KubernetesClusterName $KubernetesClusterName -ServiceAccountName $svcAccountName -KubernetesResourceNamespace $KubernetesResourceNamespace
        
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

# Create JSON object that will be used to create an Azure DevOps Environment AKS Resource
function New-AKS-Service-Connection-Object 
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName, # AKS cluster name

        [Parameter(Mandatory=$true)]
        [string]$SubscriptionId, # Azure subscription ID that AKS cluster is provisioned in

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionName, # Azure DevOps Kubernetes Service Connection to use for AKS resource

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectId, # Azure DevOps project ID

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectName, # Azure DevOps project name

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.        
    )

    kubectl config use-context $KubernetesClusterName | Out-Null
    
    if($LASTEXITCODE -ne 0)
    {
        Write-Error "Can't connect to Kubernetes cluster! Please check that your connection is properly set up."
        exit 1
    }

    az account set --subscription $SubscriptionId

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

# Create JSON object that will be used to create an Azure DevOps Environment Generic Kubernetes Resource
function New-Generic-Kubernetes-Service-Connection-Object 
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$KubernetesClusterUrl, # Kubernetes cluster server AbsoluteUri (format: https://<kubernetes_cluster_url>) which is required to create a Generic Kubernetes Resource 

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountName, # Service account name that will be used to generate the service account, secret and rolebinding in the namespace where Resource will be deployed in the Kubernetes cluster
        
        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountCertificate, # Base64-encoded certificate used for Service Account authorization in Kubernetes cluster (generated in Service Account Secret)

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountApiToken, # Base64-encoded Kubernetes API server token used for Service Account authorization in Kubernetes cluster (generated in Service Account Secret)

        [Parameter(Mandatory=$true)]
        [string]$ServiceConnectionName, # Azure DevOps Kubernetes service connection name

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectId, # Azure DevOps project ID

        [Parameter(Mandatory=$true)]
        [string]$ADOProjectName, # Azure DevOps project name

        [Parameter(Mandatory = $false)]
        [boolean]$AcceptUntrustedCertificates = $false, # Set to true if Kubernetes cluster uses default self-signed TLS certificate (untrusted by default). Defaults to FALSE.

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

# Generate a new Service Account with respective Secret and RoleBinding in the namespace that Azure DevOps Environments Kubernetes Resource will be deployed to
function New-Kubernetes-ServiceAccount
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$KubernetesClusterName, # Kubernetes cluster name

        [Parameter(Mandatory = $true)]
        [string]$KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment

        [Parameter(Mandatory = $true)]
        [string]$ServiceAccountName # Kubernetes Service Account name to use during creation
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

    kubectl config use-context $KubernetesClusterName | Out-Null
    
    if($LASTEXITCODE -ne 0)
    {
        Write-Error "Can't connect to Kubernetes cluster! Please check that your connection is properly set up."
        exit 1
    }

    Write-Debug "Checking if Kubernetes Namespace exists..."
    $kubernetesNamespace = kubectl get namespace $KubernetesResourceNamespace --ignore-not-found=true

    if(-not $kubernetesNamespace)
    {
        Write-Debug "Kubernetes Namespace $KubernetesResourceNamespace doesn't exist - creating..."
        kubectl create namespace $KubernetesResourceNamespace | Out-Null
    }

    Write-Debug "Creating respective Kubernetes resources in $KubernetesResourceNamespace namespace..."

    kubectl apply -f "$tempOutputPath/serviceaccount.yml" | Out-Null
    kubectl apply -f "$tempOutputPath/secret.yml" | Out-Null
    kubectl apply -f "$tempOutputPath/rolebinding.yml" | Out-Null

    Write-Debug "ServiceAccount $ServiceAccountName with Secret and RoleBinding created in $KubernetesResourceNamespace!"
}

# This function checks if the Azure DevOps Kubernetes Resource already exists in the respective Azure DevOps Environment
function Test-ADO-Kubernetes-Resource-Exists
{
    Param
    (
        [Parameter(Mandatory = $true)]
        $AzureDevOpsUrl, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
        [Parameter(Mandatory=$true)]
        [string]$EnvironmentId, # Azure DevOps Environment ID

		[Parameter(Mandatory=$true)]
        [string]$ResourceName, # Azure DevOps Environment Kubernetes Resource name

        [Parameter(Mandatory=$true)]
        [PSObject]$AuthHeader, # Required to call Azure DevOps REST API

        [Parameter(Mandatory = $false)]
        [string]$AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.
    )

    $adoResourcesUrl = $AzureDevOpsUrl + "/_apis/distributedtask/environments/$($EnvironmentId)?expands=resourceReferences&$AzureDevOpsApiVersion"
    Write-Debug "Checking if resource $ResourceName exists in Azure DevOps environment with id: $EnvironmentId. Calling url: $adoResourcesUrl"
    $adoResource = (Invoke-RestMethod -Uri $adoResourcesUrl -Method GET -Headers $AuthHeader -ContentType 'application/json' -MaximumRedirection 0 -MaximumRetryCount 3 -RetryIntervalSec 30).resources | Where-Object {$_.name -eq $ResourceName}

    if(-not $adoResource)
    {
        Write-Debug "Resource $ResourceName doesn't exist in Azure DevOps Environment with ID $EnvironmentId"
        return $false
    }

    return $true
}

Export-ModuleMember Get-ADO-Environment, Get-ADO-Environment-Resources, Get-ADO-Environment-Kubernetes-Resource, New-Service-Connection, New-ADO-Environment-Kubernetes-Resource