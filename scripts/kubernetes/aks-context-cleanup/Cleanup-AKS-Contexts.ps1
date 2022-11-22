# This script cleans up unused AKS cluster contexts. It will retrieve information about all AKS clusters in all subscriptions that the logged in account has access to.
# Next, it will check all Kubernetes contexts that exist on the respective client towards retrieved AKS clusters - if a context exists but an AKS cluster doesn't it will prompt you for confirmation to remove context for this cluster.
# If -FullCleanup switch is provided upon script execution, it will also cleanup user and cluster section in kubeconfig file for the respective context.
# If you don't confirm cleanup, context will be skipped. 
# There may be cases when you have configured context to non-AKS clusters for example, therefore there's a confirmation propmpt for additional reassurance that only relevant data will be cleaned up.

# Note: you need kubectl and Azure CLI installed in order to run this script.

# Example usage:
# 1. Clean up only AKS context: Cleanup-AKS-Contexts.ps1
# 2. Clean up AKS context in addition to cluster and user data for the respective context in kubeconfig file: Cleanup-AKS-Contexts.ps1 -FullCleanup

param (    
    [switch]$FullCleanup # If this switch is provided, both Kubernetes context, cluster and user section will be removed from kubeconfig file. Default behavious is only to remove the context section.
)

$global:DebugPreference = "Continue";

$confirmPromptTitle = 'Confirm AKS context removal'
$actionChoices = '&Yes', '&No'

az login

$kubeContexts = [System.Collections.ArrayList]@()
kubectl config get-contexts | Select-Object -Skip 1 | ForEach-Object {$kubeContexts += $_} # Remove column names, keep only value rows

$azSubscriptions = az account subscription list | ConvertFrom-Json 
$allAKSClustersArrayList = [System.Collections.ArrayList]@()

foreach($subscription in $azSubscriptions)
{
    Write-Debug "Getting AKS clusters in subscription $($subscription.displayName)..."

    az account set --name $subscription.subscriptionId
    $aksClusters = az aks list | ConvertFrom-Json
    
    if($aksClusters.count -eq 0)
    {
        Write-Debug "No AKS clusters exist in subscription $($subscription.displayName) - skipping..."
        continue
    }

    Write-Debug "Found $($aksClusters.count) AKS clusters - added to the list."
    $aksClusters | ForEach-Object {$allAKSClustersArrayList.Add($_.name)}
    
}

foreach ($kubeContext in $kubeContexts)
{
    $kubeContextParsed = $kubeContext -split "\s{1,}"
    Write-Debug "Checking if Kubernetes context $($kubeContextParsed[1]) is a valid AKS cluster..."

    if($allAKSClustersArrayList -match $kubeContextParsed[1])
    {
        Write-Debug "AKS cluster exists and context is still valid - skipping..."
        continue
    }

    $userQuestion = "Cluster no longer exists or is not an AKS cluster - Do you want to remove $($kubeContextParsed[1]) context?"
    $userChoice = $Host.UI.PromptForChoice($confirmPromptTitle, $userQuestion, $actionChoices, 1)
    
    if ($userChoice -ne 0)
    {
        Write-Host "Your choice is No - skipping $($kubeContextParsed[1]) context..."
        continue
    }
    
    Write-Host "Your choice is Yes - deleting $($kubeContextParsed[1]) context..."
    kubectl config unset contexts.$($kubeContextParsed[1])
    
    if($FullCleanup)
    {
        Write-Debug "Full cleanup is enabled - deleting cluster and user information from kubeconfig file..."
        kubectl config unset clusters.$($kubeContextParsed[2]) && kubectl config unset users.$($kubeContextParsed[3])
    }

    Write-Debug "$($kubeContextParsed[1]) context removed!"
}

Write-Debug "Cleanup completed! :)"