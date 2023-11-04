# OAuth2 Proxy

This folder includes a collection of templates and a PowerShell script that automate deployment of OAuth2 Proxy to support OAuth 2.0 authentication for applications that are hosted in Kubernetes clusters and use NGINX Ingress Controller.

Please see detailed explanation and walkthrough in this blog post: [Setting Up OAuth 2.0 Authentication for Applications in AKS With NGINX and OAuth2 Proxy](https://kristhecodingunicorn.com/post/k8s_nginx_oauth)

In order to run the script following pre-requisites must be in place:

- Add NGINX Ingress Controller ```auth_request``` directive annotations that are mentioned in following section of the walkthrough to the Ingress of your application: [Configure NGINX Ingress Controller](https://www.kristhecodingunicorn.com/post/aks-oauth2-proxy-with-nginx-ingress-controller/#configure-nginx-ingress-controller)

- PowerShell 7+, Azure CLI, kubectl and Helm CLI (if deploying with Helm will be used) must be installed. Don't forget to set Kubernetes Context to the correct cluster prior to script execution ;-)

You can execute the script like this (dummy values are used to better illustrate example usage):

1. Deploy OAuth2 Proxy with Kubernetes YAML templates and create new OAuth2 Proxy Azure AD application and cookie secret:
```./Deploy-OAuth2-Proxy.ps1 -ApplicationNamespace test-app -ApplicationUrl https://testapp.com -TenantId b83f0b76-9b93-456c-b420-87a70dc73742 -KubernetesClusterIssuerName clusterissuer-dev -CreateAzureADApp -ClientSecretExpirationDate 2023-12-31```

2. Deploy OAuth2 Proxy with Helm and use existing OAuth2 Proxy Azure AD application and cookie secret:

```./Deploy-OAuth2-Proxy.ps1 -ApplicationNamespace test-app -ApplicationUrl https://test-app.com -TenantId b83f0b76-9b93-456c-b420-87a70dc73742 -KubernetesClusterIssuerName clusterissuer-dev -ClientId 3e01d62a-3fe1-4d79-8bef-d054253c1eb8 -ClientSecret G$dj*&8jR]FDCp-7l5U$j4X!qDtSkiOW -ApplicationName test-app -CookieName testappcookie -CookieSecret "V$Nh3?hsk+8CQt-4Edr[3WP37E!B%p@a"```
