# This script is related to following blog post on resolving issues with collecting performance
# counters for Application Insights from ASP.NET applications: [TODO]
# It will retrieve existing IIS application pools, filter out entries if applicable, and add them
# to the provided Windows local group.

$appPools = (Get-IISAppPool).Name

# If you want to have some advanced filtering to not add all existing application pools to a group, you can comment out and modify the line below.
# Here you can use regex expressions to filter out app pools that you're not interested in.

# $appPools=Get-IISAppPool | Where-Object {$_.Name -like 'test*'} | Select -ExpandProperty Name

$formattedAppPools = New-Object System.Collections.ArrayList
$groupName = "Performance Monitor Users"
$group = [ADSI]"WinNT://$Env:ComputerName/$groupName,group"

foreach($ap in $appPools)
{
    $formattedAP = "IIS APPPOOL\$ap"
    $formattedAppPools.Add($formattedAP) > $null
}

foreach($appPool in $formattedAppPools)
{
    Write-Output "Adding $appPool to $groupName"
    
    # Below block originates from: https://stackoverflow.com/a/25279322
    $ntAccount = New-Object System.Security.Principal.NTAccount($appPool)
    $strSID = $ntAccount.Translate([System.Security.Principal.SecurityIdentifier])
    $user = [ADSI]"WinNT://$strSID"
    $group.Add($user.Path)
}
