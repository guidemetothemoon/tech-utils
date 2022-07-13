# This script includes commands that can help you set up OAuth2 Proxy for your application
# See detailed walkthrough here: https://kristhecodingunicorn.com/post/k8s_nginx_oauth/

# ! Pre-requisites: 
#   - add annotations mentioned in this section of the walkthrough to the Ingress of your application: https://kristhecodingunicorn.com/post/k8s_nginx_oauth/#configure-nginx-ingress-controller
#   - update configuration and replace placeholders in oauth2-proxy.yaml according to the needs of your application

# 1. Set up OAuth2 Proxy application in Azure AD

# 2. Generate Cookie Secret

# 3. Create Kubernetes Secrets for Client ID, Client Secret and Cookie Secret

# 4. Install OAuth2 Proxy from the oauth2-proxy.yaml template