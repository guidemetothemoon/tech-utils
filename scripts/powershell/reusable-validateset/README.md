This folder contains examples that were used in the blog post about creating reusable ValidateSets in PowerShell: [Reusable ValidateSets in PowerShell](https://www.kristhecodingunicorn.com/post/powershell-reusable-validatesets)
 
 - [modules/common](./modules/common/) contains a PowerShell module with a common ValidateSet class that contains all the reusable ValidateSets.
 - [Test-RegularValidateSet.ps1](./Test-RegularValidateSet.ps1) is a simple PowerShell script that utilizes regular ValidateSet on the parameter by hard-coding the values. It can be tested by calling it with an invalid value to see if it fails: `./Test-ReusableValidateSet.ps1 -DeploymentEnvironment Test` or with one of the valid values defined.
 - [Test-ReusableValidateSet.ps1](./Test-ReusableValidateSet.ps1) is a PowerShell script that utilizes a reusable ValidateSet that was defined in the common PowerShell module. It can be teste in the same manner as the above script.
