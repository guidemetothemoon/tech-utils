param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Development", "Staging", "Production")]
    $DeploymentEnvironment
)

Write-Host $DeploymentEnvironment