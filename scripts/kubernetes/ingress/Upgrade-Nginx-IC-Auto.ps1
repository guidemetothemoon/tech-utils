# This script provides guidance and necessary commands to automatically upgrade Ingress Controller with zero downtime. Script has been used to upgrade NGINX Ingress Controller in Azure Kubernetes Service clusters
# but it can be easily adjusted to any other Kubernetes infrastructure as well.

# Before doing the upgrade, make a note of following information:
# Ensure that the command shell session is allowed to execute Azure commands (az login command to your service ;))

param (    
    [Parameter(Mandatory = $true)] [string]$ClusterId, # Id of the Kubernetes cluster where Ingress Controller is deployed
    [Parameter(Mandatory = $true)] [string]$ClusterResourceGroup, # Resource group that AKS cluster was deployed to
    [Parameter(Mandatory = $true)] [string]$DnsZoneName, # DNS zone that's being used by applications running in respective AKS cluster
    [Parameter(Mandatory = $true)] [string]$DnsResourceGroup, # Resource group that DNS zone is created in
    [Parameter(Mandatory = $false)] [string]$SubscriptionId # (Optional) Azure subscription where DNS zone is created - it will be set as active subscription for the shell session
)

$global:DebugPreference = "Continue";

function Update-DNS()
{
    param
	(
        [Parameter(Mandatory=$true)][string]$DnsZoneName,
        [Parameter(Mandatory=$true)][string]$DnsResourceGroup,
        [Parameter(Mandatory=$true)][string]$IpToRemove,
        [Parameter(Mandatory=$true)][string]$IpToAdd
	)

    # Get DNS records pointing to the IC IP that is about to be removed
    $dns_recs = Get-DnsRecs -DnsZoneName $DnsZoneName -DnsResourceGroup $DnsResourceGroup -IpToCheck $IpToRemove
    
    while ($dns_recs.count -ne 0)
    {
        Write-Debug "Updating DNS records..."
        $dns_recs | ForEach-Object -Parallel {
            $DebugPreference = "Continue";
            Write-Debug "Removing $($using:IpToRemove) $($_.name) IP $($_.arecords.ipv4Address) with updated Ingress Controller External IP $($using:IpToAdd)"
            az network dns record-set a add-record --resource-group $using:DnsResourceGroup --zone-name $using:DnsZoneName --record-set-name $_.name --ipv4-address $using:IpToAdd
            az network dns record-set a remove-record --resource-group $using:DnsResourceGroup --zone-name $using:DnsZoneName --record-set-name $_.name --ipv4-address $using:IpToRemove
        } -ThrottleLimit 3 # here you can customize parallel threads count based on how many records you have but I wouldn't recommend to use more that 15 depending on how resourceful your system is
        
        # We need to check if any new DNS records were added pointing on the to-be-removed IP while we were updating DNS records so that we don't leave any DNS records dangling
        $dns_recs = Get-DnsRecs -DnsZoneName $DnsZoneName -DnsResourceGroup $DnsResourceGroup -IpToCheck $IpToRemove
    }
    
    # Now wait for all traffic to be drained from original IC and moved to the new IC - check DNS resolution in the meantime to confirm that all DNS records are updated
    Write-Debug "Waiting for DNS records to be resolved to new IP..."
    $updated_dns_recs = Get-DnsRecs -DnsZoneName $DnsZoneName -DnsResourceGroup $DnsResourceGroup -IpToCheck $IpToAdd

    do
    {
        # Get DNS records that point to the new IP but are still being resolved to the old IP
        $dns_resolution_res = $updated_dns_recs | Where-Object { (Resolve-DnsName -Name $_.fqdn).IPAddress -eq $IpToRemove }
        
        if($dns_resolution_res.Count -ne 0)
        {
            Write-Debug "Not all DNS records are updated yet - sleeping for 1 minute before re-try..."
            Start-Sleep -Seconds 60
        }
    }
    while($dns_resolution_res.Count -ne 0)
    Write-Debug "All DNS records have now been resolved!"
    
}  

function Get-DnsRecs()
{
    param
	(
        [Parameter(Mandatory=$true)][string]$DnsZoneName,
        [Parameter(Mandatory=$true)][string]$DnsResourceGroup,
        [Parameter(Mandatory=$true)][string]$IpToCheck
	)

    $all_dns_recs = az network dns record-set a list -g $DnsResourceGroup -z $DnsZoneName
    $dns_recs_to_update = $all_dns_recs | ConvertFrom-Json -Depth 4 | Where-Object { $_.arecords.ipv4Address -eq $IpToCheck }
    Write-Debug "Found $($dns_recs_to_update.count) DNS records using IP $IpToCheck in DNS zone $DnsZoneName..."

    return $dns_recs_to_update
}

function Get-Ingress-Pip()
{
    param
	(
        [Parameter(Mandatory=$true)][string]$IngressNs
    )

    # Get external IP of the newly created Ingress Controller (service of type LoadBalancer in $temp_ingress_ns namespace)
    $retryCount = 0
    $ingress_ip

    do {

        if ($retryCount -ge 10) {
            Write-Warning "Can't retrieve external IP of Ingress Controller after more than 10 attempts - please update the deployment or abort operation!"
        }

        $ingress_ip = k get svc -n $IngressNs --output jsonpath='{.items[?(@.spec.type contains 'LoadBalancer')].status.loadBalancer.ingress[0].ip}' # get external ip of LoadBalancer service
    
        if ($null -eq $ingress_ip) {
            Write-Debug "External IP of Ingress Controller is not ready - sleeping for 10 seconds before re-try..."
            Start-Sleep -Seconds 10
            $retryCount++
        }
        else {
            Write-Debug "External IP of Ingress Controller is $ingress_ip"
            return $ingress_ip
        }

    } while ($null -eq $ingress_ip)

}

# 0 - Set alias for kubectl to not type the whole command every single time ;)
Write-Debug "Setting alias for kubectl command.."
Set-Alias -Name k -Value kubectl

if ($null -ne $SubscriptionId) {
    Write-Debug "Setting active Azure subscription to $SubscriptionId .."
    az account set --subscription $SubscriptionId # Set active subscription to the one where your DNS zones are defined
}

# 1 - Prepare namespace and Helm charts before creating temp Ingress Controller
Write-Debug "Setting active Kubernetes cluster to $ClusterId .."
k config use-context $ClusterId

$temp_ingress_ns = "ingress-temp"
$create_temp_ingress_ns = $null -eq (k get ns $temp_ingress_ns --ignore-not-found=true)

if ($create_temp_ingress_ns) 
{
    Write-Debug "ingress-temp namespace doesn't exist - creating..."
}
else 
{
    Write-Debug "ingress-temp namespace already exists - creating another namespace..."
    $ns_guid = (New-Guid).Guid.Substring(0, 8)
    $temp_ingress_ns = -join ($temp_ingress_ns, $ns_guid)
}

k create ns $temp_ingress_ns

# Add old and new Helm charts to ensure that the repo is up-to-date - here you can update the repo to any other repo you would like to use to deploy NGINX Ingress Controller
Write-Debug "Adding old and new Helm Charts repo for NGINX Ingress..."

helm repo add nginx-stable https://helm.nginx.com/stable
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 2 - Create temp Ingress Controller based on the same Helm chart as the existing Ingress Controller that will be upgraded
Write-Debug "Creating temporary NGINX Ingress Controller based on the old Helm chart..."
helm upgrade nginx-ingress-temp stable/nginx-ingress --install --namespace $temp_ingress_ns --set controller.config.proxy-buffer-size="32k" --set controller.config.large-client-header-buffers="4 32k" --set controller.replicaCount=2 --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux --set controller.metrics.service.annotations."prometheus\.io/port"="10254" --set controller.metrics.service.annotations."prometheus\.io/scrape"="true" --set controller.metrics.enabled=true --version=1.41.2 

Write-Debug "Retrieving External IP of the original and temporary Ingress Controller... "
$original_ingress_ip = k get svc -n ingress-basic --output jsonpath='{.items[?(@.spec.type contains 'LoadBalancer')].status.loadBalancer.ingress[0].ip}' # get External IP of original Ingress Controller - it's deployed to ingress-basic namespace by default
Write-Debug "External IP of the original Ingress Controller is $original_ingress_ip"

# Get external IP of the newly created Ingress Controller (service of type LoadBalancer in $temp_ingress_ns namespace)
$temp_ingress_ip = Get-Ingress-Pip($temp_ingress_ns)


# Commands to monitor traffic in both Ingress Controllers to identify when the traffic is only routed to the temporary IC so that the original IC can be taken offline
# For manual check of traffic flow in original and temporary Ingress Controller
#kubectl logs -l component=controller -n ingress-basic -f # Monitor traffic in original IC
#kubectl logs -l component=controller -n ingress-temp -f # Monitor traffic in temporary IC

# 4 - Update DNS records to route traffic to temp Ingress Controller
Update-DNS -DnsZoneName $DnsZoneName -DnsResourceGroup $DnsResourceGroup -IpToRemove $original_ingress_ip -IpToAdd $temp_ingress_ip

# 5 - Once DNS records were updated and all traffic has been re-routed to temp IC, uninstall original Ingress Controller with Helm and install new Ingress Controller with Helm
# In this case new Ingress Controller is configured to use Public IP of Azure Load Balancer and not create a new IP
Write-Debug "Getting cluster's Load Balancer Public IP..."
$cluster_lb_rg = az aks show --resource-group $ClusterResourceGroup --name $ClusterId --query nodeResourceGroup
$cluster_lb_ip = (az network public-ip list -g $cluster_lb_rg --query "[?tags.type=='aks-slb-managed-outbound-ip']" | ConvertFrom-Json)[0].ipAddress  # Public IP of Azure Load Balancer that AKS cluster is connected to
Write-Debug "$ClusterId cluster's Azure Load Balancer Public IP is $cluster_lb_ip..."

Write-Debug "Uninstalling original NGINX IC and deploying an updated version to ingress-basic namespace..."
helm uninstall nginx-ingress -n ingress-basic
helm upgrade nginx-ingress ingress-nginx/ingress-nginx --install --create-namespace --namespace ingress-basic --set controller.config.proxy-buffer-size="32k" --set controller.config.large-client-header-buffers="4 32k" --set controller.replicaCount=2 --set controller.nodeSelector."kubernetes\.io/os"=linux --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux --set-string controller.metrics.service.annotations."prometheus\.io/port"="10254" --set-string controller.metrics.service.annotations."prometheus\.io/scrape"="true" --set controller.metrics.enabled=true --set controller.service.loadBalancerIP=$cluster_lb_ip #you can also remove loadBalancerIP if you don't want new Ingress Controller to use Azure Load Balancer's Public IP - then new external IP will be generated automatically for this new IC

Get-Ingress-Pip("ingress-basic")

# Commands to monitor the newly created Ingress Controller since the initial one was removed in previous step - be aware that the Kubernetes label for in new NGINX Ingress Controller template has changed!
# For manual check of traffic flow in original and temporary Ingress Controller:

#kubectl logs -l app.kubernetes.io/component=controller -n ingress-basic -f # New IC
#kubectl logs -l component=controller -n ingress-temp -f # Temporary IC, should still be actively monitoring as per actions in step 3

# 7 - Redirect traffic back to the newly created Ingress Controller and monitor traffic routing together with DNS resolution
Update-DNS -DnsZoneName $DnsZoneName -DnsResourceGroup $DnsResourceGroup -IpToRemove $temp_ingress_ip -IpToAdd $cluster_lb_ip

# 8 - Remove temp resources once traffic is drained from temporary IC and newly created IC is fully in use and successfully running in respective Kubernetes cluster
Write-Debug "Cleaning up temp NGINX IC Helm deployment and namespace..."
helm uninstall nginx-ingress-temp -n $temp_ingress_ns
k delete ns $temp_ingress_ns

Write-Debug "Ingress Controller has been successfully updated!"