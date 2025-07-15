using module ./modules/common/CommonValidateSetsClass.psm1
# using module is required and MUST be defined on top of the script

param(
    [Parameter(Mandatory = $true)]
    [ValidateSet([ValidDeploymentEnvironments], ErrorMessage = "Provided value '{0}' is not part of the supported values in the set: '{1}'", IgnoreCase = $false)]
    $DeploymentEnvironment
)

# Import the module containing the reusable ValidateSet class - you can also do it outside of the script itself
# but it must be done prior to calling the respective script/function
Import-Module ./modules/common/Common.psd1 -Force
Write-Host $DeploymentEnvironment