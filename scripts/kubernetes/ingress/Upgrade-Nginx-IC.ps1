# This script provides guidance and necessary commands to upgrade Ingress Controller with zero downtime. Script has been used to upgrade NGINX Ingress Controller in Azure Kubernetes Service clusters
# but it can be easily adjusted to any other Kubernetes infrastructure as well.

# Before doing the upgrade, make a note of following information:
# 1 - External IP of the original Ingress Controller
# 2 - Azure Load Balancer Public IP for the current AKS cluster (if you want the final Ingress Controller to use load balancer's public IP and not create a new one, see this article for more information: )

# 0 - Set alias for kubectl to not type the whole command every single time ;)
Set-Alias -Name k -Value kubectl

#Log in to Azure and set proper subscription active in order to be able to update DNS records (not applicable if you're using another DNS provider
az login
az account set --subscription mySubscription # Set active subscription to the one where your DNS zones are defined

# 1 - Prepare namespace and Helm charts before creating temp Ingress Controller

k config use-context TestKubeCluster
k create ns ingress-temp

# Add old and new Helm charts to ensure that the repo is up-to-date:
helm repo add nginx-stable https://helm.nginx.com/stable
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

# 2 - Create temp Ingress Controller based on the same Helm chart as the existing Ingress Controller that will be upgraded
helm upgrade nginx-ingress-temp stable/nginx-ingress --install --namespace ingress-temp --set controller.config.proxy-buffer-size="32k" --set controller.config.large-client-header-buffers="4 32k" --set controller.replicaCount=2 --set controller.nodeSelector."beta\.kubernetes\.io/os"=linux --set defaultBackend.nodeSelector."beta\.kubernetes\.io/os"=linux --set controller.metrics.service.annotations."prometheus\.io/port"="10254" --set controller.metrics.service.annotations."prometheus\.io/scrape"="true" --set controller.metrics.enabled=true --version=1.41.2 

$original_ingress_ip = "10.10.10.10" # replace with the External IP of existing Ingress Controller

#Get external IP of the newly created Ingress Controller (service of type LoadBalancer in ingress-temp namespace)
$temp_ingress_ip = k get svc -n ingress-temp --output jsonpath='{.items[?(@.spec.type contains 'LoadBalancer')].status.loadBalancer.ingress[0].ip}' # get external ip of LoadBalancer service

# 3 - Monitor traffic in both Ingress Controllers to identify when the traffic is only routed to the temporary IC so that the original IC can be taken offline
kubectl logs -l component=controller -n ingress-basic -f # Monitor traffic in original IC
kubectl logs -l component=controller -n ingress-temp -f # Monitor traffic in temporary IC

# 4 - Update DNS records to route traffic to temp Ingress Controller
# Please note: for even further automation, the code that is used to retrieve, filter and update DNS records can be moved out to a separate function to avoid duplication.
# Since this script is aimed for educating purposes, I've consciously duplicated the steps instead of creating a separate function

$dns_recs = az network dns record-set a list -g myresourcegroup -z mydnszone.com

# Check in the DNS zone how many records are there that are connected to the original IC's IP
$cluster_dns_recs = $dns_recs | convertfrom-json -Depth 4 | Where-Object {$_.arecords.ipv4Address -eq $original_ingress_ip}
$cluster_dns_recs.count

$cluster_dns_recs | ForEach-Object -Parallel {
	Write-Output "Updating $($_.name) IP $($_.arecords.ipv4Address) with updated Ingress Controller External IP $using:temp_ingress_ip"
	#az network dns record-set a add-record --resource-group myresourcegroup --zone-name mydnszone.com --record-set-name $_.name --ipv4-address  $using:temp_ingress_ip
    #az network dns record-set a remove-record --resource-group myresourcegroup --zone-name mydnszone.com --record-set-name $_.name --ipv4-address $using:original_ingress_ip
} -ThrottleLimit 3 # here you can customize parallel threads count based on how many records you have but I wouldn't recommend to use more that 15 depending on how resourceful your system is

# Once you've updated DNS records you will need to load them again
$dns_recs = az network dns record-set a list -g myresourcegroup -z mydnszone.com

# Verify that there are no more DNS records that are connected to the original IC's IP
$cluster_dns_recs = $dns_recs | convertfrom-json -Depth 4 | Where-Object {$_.arecords.ipv4Address -eq $original_ingress_ip}
$cluster_dns_recs.count # Should be 0 by now

# Now wait for all traffic to be drained from original IC and moved to the temp IC
# You can check DNS resolution in the meantime to confirm that all DNS records are updated

# For few exisitng DNS records - check what those are resolved to
foreach($dnsrec in $cluster_dns_recs) {
	$res = Resolve-DnsName -Name $dnsrec.fqdn
	Write-Output $res
}

# For large amount of DNS records - Faster check if all the DNS records have been properly updated
$dns_resolv_Res = $dns_recs | Where-Object {$_.arecords.ipv4Address -eq $temp_ingress_ip -and (Resolve-DnsName -Name $_.fqdn).IPAddress -ne $temp_ingress_ip}

# 5 - Once DNS records were updated and all traffic has been re-routed to temp IC, uninstall original Ingress Controller with Helm and install new Ingress Controller with Helm
# In this case new Ingress Controller is configured to use Public IP of Azure Load Balancer and not create a new IP
helm uninstall nginx-ingress -n ingress-basic
helm upgrade nginx-ingress ingress-nginx/ingress-nginx --install --create-namespace --namespace ingress-basic --set controller.config.proxy-buffer-size="32k" --set controller.config.large-client-header-buffers="4 32k" --set controller.replicaCount=2 --set controller.nodeSelector."kubernetes\.io/os"=linux --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux --set-string controller.metrics.service.annotations."prometheus\.io/port"="10254" --set-string controller.metrics.service.annotations."prometheus\.io/scrape"="true" --set controller.metrics.enabled=true --set controller.service.loadBalancerIP="00.00.00.000" #remove loadBalancerIP if Ingress Controller will not use Azure Load Balancer's Public IP

# 6 - Monitor the newly created Ingress Controller since the initial one was removed in previous step - be aware that the Kubernetes label for in new NGINX Ingress Controller template has changed!
kubectl logs -l app.kubernetes.io/component=controller -n ingress-basic -f # New IC
kubectl logs -l component=controller -n ingress-temp -f # Temporary IC, should still be actively monitoring as per actions in step 3

# 7 - Redirect traffic back to newly created Ingress Controller and monitor traffic routing together with DNS resolution
# Repeat step 4, just like below:
# Please note: for even further automation, the code that is used to retrieve, filter and update DNS records can be moved out to a separate function to avoid duplication.
# Since this script is aimed for educating purposes, I've consciously duplicated the steps instead of creating a separate function

$new_ingress_ip = "00.00.00.000" # Public IP of newly created Ingress Controller

#Update DNS records to route traffic to temp Ingress Controller
$dns_recs = az network dns record-set a list -g myresourcegroup -z mydnszone.com

# Check in the DNS zone how many records are there that are connected to the temp IC's IP
$cluster_dns_recs = $dns_recs | convertfrom-json -Depth 4 | Where-Object {$_.arecords.ipv4Address -eq $temp_ingress_ip}
$cluster_dns_recs.count

$cluster_dns_recs | ForEach-Object -Parallel {
	Write-Output "Updating $($_.name) IP $($_.arecords.ipv4Address) with updated Ingress Controller External IP $using:new_ingress_ip"
	az network dns record-set a add-record --resource-group myresourcegroup --zone-name mydnszone.com --record-set-name $_.name --ipv4-address  $using:new_ingress_ip
    az network dns record-set a remove-record --resource-group myresourcegroup --zone-name mydnszone.com --record-set-name $_.name --ipv4-address $using:temp_ingress_ip
} -ThrottleLimit 3 # here you can customize parallel threads count based on how many records you have but I wouldn't recommend to use more that 15 depending on how resourceful your system is

# Once you've updated DNS records you will need to load them again
$dns_recs = az network dns record-set a list -g myresourcegroup -z mydnszone.com

# Verify that there are no more DNS records that are connected to the temp IC's IP
$cluster_dns_recs = $dns_recs | convertfrom-json -Depth 4 | Where-Object {$_.arecords.ipv4Address -eq $temp_ingress_ip}
$cluster_dns_recs.count # Should be 0 by now

# Now wait for all traffic to be drained from temp IC and moved to the new IC
# You can check DNS resolution in the meantime to confirm that all DNS records are updated

# For few exisitng DNS records - check what those are resolved to
foreach($dnsrec in $cluster_dns_recs) {
	$res = Resolve-DnsName -Name $dnsrec.fqdn
	Write-Output $res
}

# For large amount of DNS records - Faster check if all the DNS records have been properly updated
$dns_resolv_Res = $dns_recs | Where-Object {$_.arecords.ipv4Address -eq $new_ingress_ip -and (Resolve-DnsName -Name $_.fqdn).IPAddress -ne $new_ingress_ip}


# 8 - Remove temp resources once traffic is drained from temporary IC and newly created IC is fully in use and successfully running in respective Kubernetes cluster
helm uninstall nginx-ingress-temp -n ingress-temp
k delete ns ingress-temp

# Final step, after all clusters are upgraded - remove DNS record for any test applications you might have created like the one from this Microsoft tutorial: