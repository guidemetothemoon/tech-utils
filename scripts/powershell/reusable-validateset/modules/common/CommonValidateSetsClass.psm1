using namespace System.Management.Automation

class ValidDeploymentEnvironments : IValidateSetValuesGenerator
{
    [string[]] GetValidValues()
    {
        $values = @(
            'Development',
            'Staging',
            'Production'
        )

        return $values
    }
}