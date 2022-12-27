# This script can be used to ...[TODO]

# Note: This script requires PowerShell 7, Azure CLI and kubectl installed. 
# Also, you will need an Azure DevOps PAT so that the script gets enough permissions to perform necessary operations.

# Example usage:
# ./New-ADO-K8s-Resource.ps1 -AccessToken "<azure_devops_pat>" -AzureDevOpsUrl "https://dev.azure.com/<organization_name>/<project_name>" -EnvironmentName "<azure_devops_environment_name>" -KubernetesClusterName "<kubernetes_cluster_name>" -KubernetesResourceNamespace "<application_namespace_in_kubernetes_cluster>" -KubernetesClusterUrl "https://<kubernetes_cluster_server_url>"

Param(
  [Parameter(Mandatory = $true)]
  $AccessToken, # Access token that is used to call Azure DevOps REST API

  [Parameter(Mandatory = $true)]
  $AzureDevOpsURL, # URL to Azure DevOps project. Please provide the URL including project name, f.ex. https://azure-devops-public-url/organization-name/project-name
  
  [Parameter(Mandatory = $true)]
  $EnvironmentName, # Name of the Azure DevOps Environment
  
  [Parameter(Mandatory = $true)]
  $KubernetesClusterName, # Kubernetes cluster name

  [Parameter(Mandatory = $true)]
  $KubernetesClusterUrl, # Kubernetes cluster server URL
  
  [Parameter(Mandatory = $true)]
  $KubernetesResourceNamespace, # Namespace of the Kubernetes Resource that will be created in Azure DevOps Environment
  
  [Parameter(Mandatory = $false)]
  $AzureDevOpsApiVersion = "api-version=7.0" # (Optional) Version of Azure DevOps REST API.  
)

$global:DebugPreference = "Continue";
Import-Module "$PSScriptRoot/modules/Manage-Ado-Environment.psm1" -Force

$user = ""
$base64Token = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user, $AccessToken)))
$authHeader = @{ Authorization = "Basic $base64Token" }

az login
az config set extension.use_dynamic_install=yes_without_prompt

Write-Debug "Get or create Azure DevOps Environment $EnvironmentName..."
$adoEnvironment = Get-ADO-Environment -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentName $EnvironmentName -AuthHeader $authHeader -CreateIfNotExists

Write-Debug "Preparing service connection for Azure DevOps Environment Kubernetes Resource $KubernetesResourceNamespace..."
$svcConnection = New-Service-Connection -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentName $EnvironmentName -KubernetesClusterName $KubernetesClusterName -KubernetesResourceNamespace $KubernetesResourceNamespace -AuthHeader $authHeader -UseGenericProvider -KubernetesClusterUrl $KubernetesClusterUrl -AcceptUntrustedCertificates $true 

Write-Debug "Creating Azure DevOps Environment Kubernetes Resource $KubernetesResourceNamespace..."
New-ADO-Environment-Resource -AzureDevOpsUrl $AzureDevOpsURL -EnvironmentId $adoEnvironment.id -ServiceConnectionId $svcConnection.id -KubernetesClusterName $KubernetesClusterName -KubernetesResourceNamespace $KubernetesResourceNamespace -AuthHeader $authHeader

Write-Debug "Success! Resource $KubernetesResourceNamespace has been created in $EnvironmentName !"