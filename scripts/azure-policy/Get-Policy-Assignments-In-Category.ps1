# This script retrieves all policy definition assignments, coming both from regular policy assignments and 
# policy initiative assignments. If any of the assigned policies belong to the requested category,
# information about those policies will be provided as output upon script execution.
# Update the $category variable to the category you want to check for.
# Please note that this script requires Azure CLI to be installed and configured. You need to be logged in to Azure CLI and target the correct subscription before executing this script.

$VerbosePreference="Continue"

$category = "Guest Configuration"
$gcPolicyDefinitions = az policy definition list --query "[?metadata.category=='$category'].{Id:id, Name:displayName}" | ConvertFrom-Json
$policyAssignments = az policy assignment list --query "[?contains(policyDefinitionId, '/providers/Microsoft.Authorization/policyDefinitions')].{Id:policyDefinitionId, Name:displayName}" | ConvertFrom-Json
$policySetDefinitionAssignments = az policy assignment list --query "[?contains(policyDefinitionId, '/providers/Microsoft.Authorization/policySetDefinitions')].{Id:policyDefinitionId, Name:displayName}" | ConvertFrom-Json

$policySetDefinitions = az policy set-definition list | ConvertFrom-Json -Depth 20

$policySetDefinitionPolicies = New-Object System.Collections.ArrayList
$policyAssignmentsOutput = New-Object System.Collections.ArrayList

Write-Verbose "Processing policies assigned via policy initiative assignment..."
foreach($psd in $policySetDefinitions)
{
    if($policySetDefinitionAssignments.Id -contains $psd.id)
    {        
        $policySetDefinitionPolicies.Add(
            @(
                @{
                    AssignmentId = $psd.id
                    AssignmentName = $psd.displayName
                    AssignmentPolicies = $psd.policyDefinitions.policyDefinitionId
                }
            )
        ) > $null
    }
}

Write-Verbose "Checking if any policy definition assignments are of category $category..."
foreach ($pa in $policyAssignments) 
{    
    if ($gcPolicyDefinitions.Id -contains $pa.Id)
    {
        $policyAssignmentsOutput.Add(
            @(
                @{
                    PolicyAssignmentId = $pa.id
                    PolicyAssignmentName = $pa.Name
                }
            )
        ) > $null
    }
}

Write-Verbose "Checking if any policy initiative assignments include policies of category $category..."
foreach($psdp in $policySetDefinitionPolicies)
{
    foreach($psdpid in $psdp.AssignmentPolicies)
    {
        if($gcPolicyDefinitions.Id -contains $psdpid)
        {
            $policyName = $gcPolicyDefinitions | Where-Object {$_.Id -eq $psdpid} | Select-Object -ExpandProperty Name
            $policyAssignmentsOutput.Add(
                @(
                    @{
                        PolicyAssignmentId = $psdpid
                        PolicyAssignmentName = $policyName
                        PolicyInitiativeId = $psdp.AssignmentId
                        PolicyInitiativeName = $psdp.AssignmentName
                    }
                )
            ) > $null
        }
    }
}

if($policyAssignmentsOutput.Count -eq 0)
{
    Write-Verbose "No policy assignments from category $category are currently assigned!"
}
else
{
    $policyAssignmentsOutput | ForEach-Object { $_ | Format-Table }
}
