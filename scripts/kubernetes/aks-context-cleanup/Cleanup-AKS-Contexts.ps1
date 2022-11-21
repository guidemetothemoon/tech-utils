$global:DebugPreference = "Continue";
az login

$aksContexts = kubectl config get-contexts
$azSubscriptions = az account subscription list | ConvertFrom-Json 
$allAKSClustersArrayList = New-Object -TypeName "System.Collections.ArrayList"

foreach($s in $azSubscriptions)
{
    Write-Debug "Getting AKS clusters in subscription $($s.displayName)..."
    az account set --name $s.subscriptionId
    $aksClusters = az aks list | ConvertFrom-Json | ForEach-Object {$allAKSClustersArrayList.Add($_.name)}
    Write-Debug "Found $($aksClusters.count) AKS clusters - added to the list."
}