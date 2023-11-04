# .NET

This folder contains a collection of scripts that can be helpful for .NET application development.

```Update-DotnetFramework.ps1```

This script can be used to automate update of target framework in multiple projects in the provided location in provided location (including subfolders) and/or removal of specific .NET target frameworks.
Please not that the script is only applicable to project files using new ```.csproj``` file format.

See more information in this blog post: [Automate .NET Target Framework Update With PowerShell](https://kristhecodingunicorn.com/techtips/update_dotnet_fw)

You can execute the script like this:

1. Add new .NET target frameworks in current location:
```.\Update-DotnetFramework.ps1 -FrameworksToAdd net6.0,net7.0```

2. Add new .NET target framework and remove existing framework in current location:
```.\Update-DotnetFramework.ps1 -FrameworksToAdd net6.0-windows -FrameworksToRemove netcoreapp3.1,net5.0```

3. Add new .NET target framework for projects in ```C:/my-repo/my-projects-dir``` folder, excluding test and VB projects:

```.\Update-DotnetFramework.ps1 -FrameworksToAdd net6.0 -ProjectsToExclude *.Test*,*`.vbproj -ProjectLocation "C:/my-repo/my-projects-dir"```
