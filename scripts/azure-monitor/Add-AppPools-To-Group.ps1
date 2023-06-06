# This script is related to following blog post on resolving issues with collecting performance
# counters for Application Insights from ASP.NET applications: https://kristhecodingunicorn.com/post/appinsights_perfcounters
# It will retrieve existing IIS application pools, filter out entries if applicable, and add them
# to the provided Windows local group.

$appPools = (Get-IISAppPool).Name

# If you want to have some advanced filtering to not add all existing application pools to a group, you can comment out and modify the line below.
# Here you can use regex expressions to filter out app pools that you're not interested in.

# $appPools=Get-IISAppPool | Where-Object {$_.Name -like 'test*'} | Select -ExpandProperty Name

$formattedAppPools = New-Object System.Collections.ArrayList
$groupName = "Performance Monitor Users"
$groupMembers = (Get-LocalGroupMember $groupName).Name

foreach($ap in $appPools)
{
    $formattedAP = "IIS APPPOOL\$ap"
    $formattedAppPools.Add($formattedAP) > $null
}

foreach($appPool in $formattedAppPools)
{
    if($groupMembers -contains $appPool)
    {
        Write-Verbose "$appPool is already a member of $groupName - skipping..."
        continue
    }
   
    Write-Verbose "Adding $appPool to $groupName"
	Add-LocalGroupMember -Group $groupName -Member $appPool
}

# Comment below section if you don't want to perform restart of IIS services as part of the script
Write-Verbose "All accounts added - executing IISRESET..."
iisreset

Write-Verbose "Success!"
exit 0