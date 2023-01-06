# This script can be used to migrate Kubernetes resources (currently AKS only) between Azure DevOps Environments. You can either migrate to a new Azure DevOps Environment while still targeting the same AKS cluster
# or you can target a new cluster by providing additional parameters when calling the script.

# Note: This script requires PowerShell 7, Azure CLI and kubectl installed. If you're not going to target new Kubernete cluster, you don't need to have kubectl.
# Also, you will need an Azure DevOps PAT so that the script gets enough permissions to perform necessary operations.

# Example usage:
# 1. Move resources from Environment1 to Environment2 and target the same cluster: Move-AKS-Environments.ps1 -AccessToken "azure-devops-pat" -AzureDevOpsUrl "https://azure-devops-url/org-name/project-name/" -SourceEnvironmentName "Environment1" -TargetEnvironmentName "Environment2" -TargetEnvironmentDescription "New target Azure DevOps Environment"
# 2. Move resources from Environment1 to Environment2 and target new cluster "NewAKSCluster": Move-AKS-Environments.ps1 -AccessToken "azure-devops-pat" -AzureDevOpsUrl "https://azure-devops-url/org-name/project-name/" -SourceEnvironmentName "Environment1" -TargetEnvironmentName "Environment2" -TargetClusterName "NewAKSCluster" -SubscriptionId "aks-cluster-azure-subscription-id"

Param(
  [Parameter(Mandatory = $true)]
  $AccessToken, # Access token that is used to call Azure DevOps REST API

  [Parameter(Mandatory = $true)]
  $AzureDevOpsURL, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
  [Parameter(Mandatory = $true)]
  $SourceEnvironmentName, # Name of the Azure DevOps Environment to migrate resources from
  
  [Parameter(Mandatory = $true)]
  $TargetEnvironmentName, # Name of the Azure DevOps Environment to migrate resources to. If it doesn't exist, it will be created first.
  
  [Parameter(Mandatory = $false)]
  $AzureDevOpsApiVersion = "api-version=7.0", # (Optional) Version of Azure DevOps REST API.
  
  [Parameter(Mandatory = $false)]
  $TargetEnvironmentDescription, # (Optional) For creation of new environment you can provide desired description that will be added upon creation.
  
  [Parameter(Mandatory = $false,
    ParameterSetName = 'NewCluster')]
  $TargetClusterName = $null, # (Optional) If cluster name isn't provided, source cluster name will be used upon migration
  
  [Parameter(Mandatory = $false,
    ParameterSetName = 'NewCluster')]
  $SubscriptionId # (Optional) If new cluster will be used for resource, Azure subscription ID must be provided to generate a service connection for the new cluster.
)

$global:DebugPreference = "Continue";
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Import-Module "$PSScriptRoot/modules/Manage-Ado-Environment.psm1" -Force # If you have saved psm1 module somewhere else, please update the file path

$user = ""
$base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $AccessToken)))
$authHeader = @{ Authorization = "Basic $base64Token" }

az login

Write-Debug "Getting information about source and target Azure DevOps Environments and Resources..."
$sourceEnvironment = Get-ADO-Environment -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentName $SourceEnvironmentName -AuthHeader $authHeader
$sourceEnvironmentResources = Get-ADO-Environment-Resources -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentId $sourceEnvironment.id -AuthHeader $authHeader
$targetEnvironment = Get-ADO-Environment -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentName $TargetEnvironmentName -AuthHeader $authHeader -CreateIfNotExists -EnvironmentDescription $TargetEnvironmentDescription

foreach($resource in $sourceEnvironmentResources.resources)
{
    # For now, this script only supports migration of Kubernetes (AKS) resources.
    if($resource.type -ne "kubernetes")
    {
        Write-Debug "Resource $($resource.name) is not a Kubernetes resource! Skipping..."
        continue
    }
    
    $kubeResource = Get-ADO-Environment-Kubernetes-Resource -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentId $sourceEnvironment.id -ResourceId $resource.id -AuthHeader $authHeader
    
    if(-not $kubeResource)
    {
        Write-Debug "This resource doesn't seem to exist anymore - skipping..."
        continue
    }

    $resourceSvcConnectionId = $kubeResource.serviceEndpointId
    $resourceKubeCluster = $kubeResource.clusterName

    if($TargetClusterName)
    {
        Write-Debug "Create Azure DevOps Kubernetes Service Connection that will be used by the Resource $($resource.name) targeting new cluster $TargetClusterName..."
        $resourceKubeCluster = $TargetClusterName
        $resourceSvcConnectionId = (New-Service-Connection -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentName $TargetEnvironmentName -KubernetesClusterName $resourceKubeCluster -KubernetesResourceNamespace $kubeResource.namespace -AuthHeader $authHeader -SubscriptionId $SubscriptionId).id
    }

    Write-Debug "Creating Azure DevOps Environment Kubernetes Resource $($kubeResource.namespace) in Environment $TargetEnvironmentName..."
    New-ADO-Environment-Kubernetes-Resource -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentId $targetEnvironment.id -ServiceConnectionId $resourceSvcConnectionId -KubernetesClusterName $resourceKubeCluster -KubernetesResourceNamespace $kubeResource.namespace -AuthHeader $authHeader
}

Write-Debug "Success! All resources have been migrated to $TargetEnvironmentName!"