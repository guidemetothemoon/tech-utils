# This script includes commands that can help you set up OAuth2 Proxy for your application
# See detailed walkthrough here: https://kristhecodingunicorn.com/post/k8s_nginx_oauth/

# ! Pre-requisites: 
#   - add annotations mentioned in this section of the walkthrough to the Ingress of your application: https://kristhecodingunicorn.com/post/k8s_nginx_oauth/#configure-nginx-ingress-controller
#   - update placeholders below according to the needs of your application

# 0. Set up initial application values
$tenantId = [your_azure_ad_tenant_id] # f.ex. "123-456-789"
$applicationName = [your_application_name] # f.ex. "testapplication" 
$applicationNamespace = [your_application_namespace] # f.ex. "testns"
$clientSecretExpirationDate = [your_azure_ad_app_client_secret_end_date] # f.ex. "2022-12-31"
$appRedirectUri = [uri]"[your_azure_ad_application_redirect_uri]" # f.ex."https://testapp.com/oauth2/callback" 
$cookieName = [your_oauth2_proxy_cookie_name] # f.ex. "_proxycookie"
$clusterIssuerName = [your_cert_cluster_issuer_name] # f.ex. "letsencrypt-http01-prod"

$applicationHostname= $appRedirectUri.Host
$tempOutputPath = [System.IO.Path]::GetTempPath()

# 1. Create OAuth2 Proxy application in Azure AD
az login --tenant $tenantId --allow-no-subscriptions

$applicationADApp = az ad app create --display-name $applicationName --sign-in-audience AzureADMyOrg --web-redirect-uris $appRedirectUri | ConvertFrom-Json
$clientId = $applicationADApp.appId
$clientSecret = $(az ad app credential reset --id $clientId --append --display-name "$applicationName-client-secret" --end-date $clientSecretExpirationDate --query password --output tsv)


# 2. Generate Cookie Secret - in Windows you can install OpenSSL.Light with Chocolatey: choco install OpenSSL.Light
$cookieSecret = openssl rand -hex 32

# 3. Create Kubernetes Secrets for Client ID, Client Secret and Cookie Secret

kubectl create secret generic client-id --from-literal=oauth2_proxy_client_id=$clientId -n $applicationNamespace
kubectl create secret generic client-secret --from-literal=oauth2_proxy_client_secret=$clientSecret -n $applicationNamespace
kubectl create secret generic cookie-secret --from-literal=oauth2_proxy_cookie_secret=$cookieSecret -n $applicationNamespace

# 4. Replace placeholders in OAuth2 Proxy deployment template with provided application values
(Get-Content "$PSScriptRoot/oauth2-proxy.yaml") `
|  ForEach-Object `
	{ `
		$_  -replace "\[ApplicationName\]", $applicationName `
		    -replace "\[ApplicationNamespace\]", $applicationNamespace `
		    -replace "\[TenantId\]", $tenantId `
                    -replace "\[CookieName\]", $cookieName `
		    -replace "\[CertClusterIssuerName\]", $clusterIssuerName `
		    -replace "\[ApplicationHostname\]", $applicationHostname `
	} `
| Set-Content "$tempOutputPath/oauth2-proxy.yaml" -Encoding UTF8

# 4. Install OAuth2 Proxy from the oauth2-proxy.yaml template
kubectl apply -f "$tempOutputPath/oauth2-proxy.yaml"
