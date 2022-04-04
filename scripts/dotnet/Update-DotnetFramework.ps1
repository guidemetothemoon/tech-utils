# This script is meant for easier and faster update of .NET target frameworks across all projects in provided location and/or removal of specific .NET target frameworks
# Please note that projects in old project format will not be updated! Only projects defined in new project format will be included in the update.
# Example Usage: To add new frameworks: .\Update-DotnetFramework.ps1 -FrameworksToAdd net5.0,net6.0
# Example Usage: To add new framework and remove existing framework: .\Update-DotnetFramework.ps1 -FrameworksToAdd net6.0-windows -FrameworksToRemove netcoreapp3.1,net5.0
# Example Usage: With project exclusion and custom location: .\Update-DotnetFramework.ps1 -FrameworksToAdd net6.0 -ProjectsToExclude *.Test*,*.vbproj -ProjectLocation "C:/my-repo/my-projects-dir"

param (
    [Parameter(Mandatory=$false)]
    [string[]]$FrameworksToAdd, # Target framework (use comma-separation for multiple values) to be added, check here for supported target frameworks: https://docs.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks
    
    [Parameter(Mandatory=$false)]
    [string[]]$FrameworksToRemove, # Target framework (use comma-separation for multiple values) to be removed, check here for supported target frameworks: https://docs.microsoft.com/en-us/dotnet/standard/frameworks#supported-target-frameworks
    
    [Parameter(Mandatory=$false)]
    [string[]]$ProjectsToExclude, # Project names to exclude, wildcard supported (use comma-separation for multiple values)
    
    [Parameter(Mandatory=$false)]
    [string]$ProjectLocation = $pwd, # Directory where to search for projects to update - subfolders will also be included by the script. If not provided, current directory will be scanned.
    
    [switch]$BuildProjects # Provide this switch to build projects automatically after the framework update
)

$VerbosePreference = "continue"

function Remove-Framework($projectFrameworkList, $projectName)
{
    if(($projectFrameworkList | Measure-Object).Count -eq 1)
    {
        Write-Verbose "At least one target framework must be defined! Aborting removal.."
        return $projectFrameworkList
    }

    foreach($framework in $FrameworksToRemove)
    {
        if(!$projectFrameworkList.Contains($framework))
        {
            Write-Verbose "$projectName doesn't target $framework. Skipping removal..."
            return $projectFrameworkList
        }
        
        Write-Verbose "Removing $TargetFramework from $projectName..."
        $projectFrameworkList.Remove($framework) | Out-Null
    }
    return $projectFrameworkList
}

function Add-Framework($projectFrameworkList, $projectName)
{
    if(($projectFrameworkList | Measure-Object).Count -eq 1 -and ($projectFrameworkList.Contains('net4*')))
    {
        Write-Verbose "Project is .NET Framework exclusive and needs manual intervention for adding new target framework. Skipping update for $projectName"
        return $projectFrameworkList
    }
    

    foreach($framework in $FrameworksToAdd)
    {
        if($projectFrameworkList.Contains($framework))
        {
            Write-Verbose "Project is already targeting $framework. Skipping $projectName"
            return $projectFrameworkList
        }

        Write-Verbose "Adding $framework to $projectName...."
        $projectFrameworkList.Add($framework) | Out-Null
    }

    return $projectFrameworkList
}


function Update-TargetFrameworks($projectToUpdate)
{   
    $projectName = Split-Path $projectToUpdate -leaf
    $projectFileContent = [xml] (Get-Content -Path $projectToUpdate)
    $projectFileContent.PreserveWhitespace = $false;
    $targetFrameworkNode =  $projectFileContent.SelectSingleNode("//TargetFrameworks")

    if($null -eq $targetFrameworkNode)
    {
        $targetFrameworkNode =  $projectFileContent.SelectSingleNode("//TargetFramework")

        if($null -ne $targetFrameworkNode)
        {
          Write-Verbose "Changing TargetFramework to TargetFrameworks property to support multiple framework targeting..."
      
          $targetFrameworkParentNode = $targetFrameworkNode.ParentNode
          $multipleFrameworksNode = $projectFileContent.CreateElement('TargetFrameworks')
      
          $multipleFrameworksNode.InnerText = $targetFrameworkNode.InnerText

          $targetFrameworkParentNode.AppendChild($multipleFrameworksNode)
          $targetFrameworkParentNode.RemoveChild($targetFrameworkNode)
          $targetFrameworkNode = $multipleFrameworksNode
          Write-Verbose "Updated TargetFramework property to TargetFrameworks!"
        }
    }

    if(-not $targetFrameworkNode)
    {
        Write-Verbose "Target framework node not found in $projectName! The project is probably in the old project format. Skipping..."
        return
    }    
    
    $targetedFrameworksList = [System.Collections.ArrayList]$targetFrameworkNode.InnerText.ToString().Split(';')

    if($FrameworksToAdd.Count -ne 0)
    {
       [System.Collections.ArrayList]$targetedFrameworksList = Add-Framework -projectFrameworkList $targetedFrameworksList -projectName $projectName
    }
    
    if($FrameworksToRemove.Count -ne 0)
    {
        [System.Collections.ArrayList]$targetedFrameworksList = @(Remove-Framework -projectFrameworkList $targetedFrameworksList -projectName $projectName)
    }

    $targetFrameworkNode.InnerText = $targetedFrameworksList -join ';'
    $projectFileContent.Save($projectToUpdate)

    Write-Verbose "Updated $projectName"
}

if(-not (Test-Path $ProjectLocation))
{
    throw "Project location $ProjectLocation doesn't exist! Please ensure that a correct path to your project files is provided."
}

$projectsToUpdate = Get-ChildItem -Path $ProjectLocation -Recurse -ErrorAction SilentlyContinue -Include *.csproj, *.vbproj -Exclude $ProjectsToExclude | Select-Object FullName


foreach($proj in $projectsToUpdate)
{
    Write-Verbose "Starting update of $($proj.FullName).."
    Update-TargetFrameworks -projectToUpdate $proj.FullName
}

Write-Verbose "Projects are successfully updated! :) "

Write-Verbose "Build solution with updated projects.."

if($BuildProjects)
{
    $solutionsToBuild = Get-ChildItem -Path $ProjectLocation -Recurse -ErrorAction SilentlyContinue -Filter *.sln

    foreach($solution in $solutionsToBuild)
    {
        dotnet restore $solution.FullName --interactive #Add this argument instead of --interactive if you want to authenticate with NuGet config file: --configfile .\nuget.config
        dotnet build $solution.FullName --no-restore
    }
}

Write-Verbose "Done!"

exit 0
