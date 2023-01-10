# This script helps you set up OAuth2 Proxy for your application, either with Kubernetes YAML templates or with official Helm chart.
# See detailed walkthrough here: https://kristhecodingunicorn.com/post/k8s_nginx_oauth

# ! Pre-requisites: 
#   - Add NGINX Ingress Controller auth_request directive annotations mentioned in this section of the walkthrough to the Ingress of your application: https://kristhecodingunicorn.com/post/k8s_nginx_oauth/#configure-nginx-ingress-controller
#   - Azure CLI, kubectl and Helm CLI (if deploying with Helm will be used) must be installed. Don't forget to set Kubernetes Context to the correct cluster ;-)

# Example usage:
# Deploy OAuth2 Proxy with Kubernetes YAML templates and create new AD app and cookie secret: ./Deploy-OAuth2-Proxy.ps1 -ApplicationNamespace test-app -ApplicationUrl https://testapp.com -TenantId b83f0b76-9b93-456c-b420-87a70dc73742 -KubernetesClusterIssuerName clusterissuer-dev -CreateAzureADApp -ClientSecretExpirationDate 2023-12-31
# Deploy OAuth2 Proxy with Helm and use existing AD app and cookie secret: ./Deploy-OAuth2-Proxy.ps1 -ApplicationNamespace test-app -ApplicationUrl https://test-app.com -TenantId b83f0b76-9b93-456c-b420-87a70dc73742 -KubernetesClusterIssuerName clusterissuer-dev -ClientId 3e01d62a-3fe1-4d79-8bef-d054253c1eb8 -ClientSecret G$dj*&8jR]FDCp-7l5U$j4X!qDtSkiOW -ApplicationName test-app -CookieName testappcookie -CookieSecret "V$Nh3?hsk+8CQt-4Edr[3WP37E!B%p@a"

Param(
  [Parameter(Mandatory = $true)]
  [string]$ApplicationNamespace, # Namespace that OAuth2 Proxy will be deployed to
  
  [Parameter(Mandatory = $true)]
  [string]$ApplicationUrl, # Application public URL to use for creating redirect URI, for example "https://myappurl.com"
  
  [Parameter(Mandatory = $true)]
  [string]$TenantId, # Azure AD tenant ID where to create OAuth2 Proxy application

  [Parameter(Mandatory = $true)]
  [string]$KubernetesClusterIssuerName, # Name of the Kubernetes cluster ClusterIssuer used to issue TLS certificates (cert-manager)
  
  [Parameter(Mandatory=$true,
    ParameterSetName = 'ExistingADApp')]
  [string]$ClientId, # If provided, an existing OAuth2 Proxy application based on provided Azure AD Application ID will be used
  
  [Parameter(Mandatory=$true,
    ParameterSetName = 'ExistingADApp')]
  [string]$ClientSecret, # If using existing Azure AD Application, client secret must be provided

  [Parameter(Mandatory=$true,
    ParameterSetName = 'AzureADApp')]
  [switch]$CreateAzureADApp, # If provided, an OAuth2 Proxy application will be created in Azure AD
  
  [Parameter(Mandatory=$true,
    ParameterSetName = 'AzureADApp')]
  [string]$ClientSecretExpirationDate, # Expiration date for OAuth2 Proxy client secret, formatted yyyy-mm-dd, for example "2022-12-31"
  
  [Parameter(Mandatory = $false)]
  [string]$ApplicationName = $ApplicationNamespace, # Application name that will be used for labeling, release name, etc. Default value equals to application Namespace.
  
  [Parameter(Mandatory = $false)]
  [string]$CookieName = "_proxycookie", # (Optional) OAuth2 Proxy cookie name
  
  [Parameter(Mandatory = $false)]
  [string]$CookieSecret, # (Optional) OAuth2 Proxy cookie secret

  [Parameter(Mandatory = $false)]
  [switch]$UseHelm # (Optional) If provided, OAuth2 Proxy will be deployed with official Helm chart. Default is Kubernetes YAML template deployment
)

$global:DebugPreference = "Continue";
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Get-CookieSecret() {
	$length = 32
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&*+-:;=?@[]^_{|}'
    $cookieSecret = ''
    for ($i = 0; $i -lt $length; $i++) {
        $cookieSecret += $chars[(Get-Random -Minimum 0 -Maximum ($chars.length - 1))]
    }
    return $cookieSecret
}



$applicationHostname= $ApplicationUrl.Host
$appRedirectUri = [uri]"$ApplicationUrl/oauth2/callback"
$tempOutputPath = [System.IO.Path]::GetTempPath()

az login --tenant $TenantId --allow-no-subscriptions

if($CreateAzureADApp)
{
	Write-Debug "Creating OAuth2 Proxy application in Azure AD tenant with ID: $TenantId"
	
	$applicationADApp = az ad app create --display-name $ApplicationName --sign-in-audience AzureADMyOrg --web-redirect-uris $appRedirectUri.AbsoluteUri | ConvertFrom-Json
	$ClientId = $applicationADApp.appId
	$ClientSecret = $(az ad app credential reset --id $ClientId --append --display-name "$ApplicationName-client-secret" --end-date $ClientSecretExpirationDate --query password --output tsv)
	
	Write-Debug "Application with ClientID: $ClientId is created."
}

if(-not $CookieSecret)
{
	Write-Debug "Generating cookie secret..."
	$CookieSecret = Get-CookieSecret
	Write-Debug "Cookie secret has been successfully created."
}

$kubeNamespace = kubectl get namespace $ApplicationNamespace --ignore-not-found=true

if(-not $kubeNamespace)
{
	Write-Debug "Kubernetes Namespace $ApplicationNamespace doesn't exist - creating..."
	kubectl create namespace $ApplicationNamespace | Out-Null
}

if($UseHelm)
{
	Write-Debug "Deploying OAuth2 Proxy with Helm..."

	(Get-Content "$PSScriptRoot/templates/values.yaml") `
	|  ForEach-Object `
		{ `
			$_  -replace "\[ApplicationName\]", $ApplicationName `
				-replace "\[ApplicationNamespace\]", $ApplicationNamespace `
				-replace "\[TenantId\]", $TenantId `
				-replace "\[ClientId\]", $ClientId `
				-replace "\[ClientSecret\]", $ClientSecret `
				-replace "\[CookieSecret\]", $CookieSecret `
				-replace "\[CookieName\]", $CookieName `
				-replace "\[CertClusterIssuerName\]", $KubernetesClusterIssuerName `
				-replace "\[ApplicationHostname\]", $applicationHostname `
		} `
	| Set-Content "$tempOutputPath/values.yaml" -Encoding UTF8

	helm repo add oauth2-proxy https://oauth2-proxy.github.io/manifests
 	helm repo update
 	helm upgrade --install $ApplicationName -n $ApplicationNamespace --create-namespace -f "$tempOutputPath/values.yaml" oauth2-proxy/oauth2-proxy
}
else
{
	Write-Debug "Deploying OAuth2 Proxy with Kubernetes YAML templates..."

	Write-Debug "Creating OAuth2 Proxy Azure AD Application Kubernetes Secrets..."
	kubectl create secret generic client-id --from-literal=oauth2_proxy_client_id=$ClientId -n $ApplicationNamespace
	kubectl create secret generic client-secret --from-literal=oauth2_proxy_client_secret=$ClientSecret -n $ApplicationNamespace
	kubectl create secret generic cookie-secret --from-literal=oauth2_proxy_cookie_secret=$CookieSecret -n $ApplicationNamespace

	(Get-Content "$PSScriptRoot/templates/oauth2-proxy.yaml") `
	|  ForEach-Object `
		{ `
			$_  -replace "\[ApplicationName\]", $ApplicationName `
				-replace "\[ApplicationNamespace\]", $ApplicationNamespace `
				-replace "\[TenantId\]", $TenantId `
				-replace "\[CookieName\]", $CookieName `
				-replace "\[CertClusterIssuerName\]", $KubernetesClusterIssuerName `
				-replace "\[ApplicationHostname\]", $applicationHostname `
		} `
	| Set-Content "$tempOutputPath/oauth2-proxy.yaml" -Encoding UTF8

	kubectl apply -f "$tempOutputPath/oauth2-proxy.yaml" -n $ApplicationNamespace
}


Write-Debug "Oauth2 Proxy is successfully deployed!"