# Copyright (c) .NET Foundation. All rights reserved.
# Licensed under the MIT license. See LICENSE file in the project root for full license information.

#####################################################################################################
## Although the NuGet package includes msbuild targets that does this same work, the ps1 files are  #
## kept for use in web site projects                                                                #
#####################################################################################################

param($installPath, $toolsPath, $package, $project)

$roslynSubFolder = 'roslyn'

if ($project -eq $null) {
    $project = Get-Project
}

$libDirectory = Join-Path $installPath 'lib\net45'
$projectRoot = $project.Properties.Item('FullPath').Value
$projectTargetFramework = $project.Properties.Item('TargetFrameworkMoniker').Value
$shouldUseRoslyn45 = $projectTargetFramework -match '4.5'
$binDirectory = Join-Path $projectRoot 'bin'

#
# Some things vary depending on which framework version you target. If you target an
# older framework, (4.5-4.7.1) then we need to change some of these.
#
$compilerVersion = $package.Version
if($package.Versions -ne $null) { $compilerVersion = @($package.Versions)[0] }
$packageDirectory = Split-Path $installPath
$compilerPackageFolderName = $package.Id + "." + $compilerVersion
$compilerPackageDirectory = Join-Path $packageDirectory $compilerPackageFolderName
$compilerPackageToolsDirectory = Join-Path $compilerPackageDirectory 'tools\roslyn472'
$csLanguageVersion = 'default'
$vbLanguageVersion = 'default'
if ($projectTargetFramework -match '^4\.5')
{
    $compilerPackageToolsDirectory = Join-Path $compilerPackageDirectory 'tools\roslyn45'
    $csLanguageVersion = '6'
    $vbLanguageVersion = '14'
}
elseif (($projectTargetFramework -match '^4\.6') -or ($projectTargetFramework -match '^4\.7$') -or ($projectTargetFramework -match '^4\.7\.[01]'))
{
    $compilerPackageToolsDirectory = Join-Path $compilerPackageDirectory 'tools\roslyn46'
    $csLanguageVersion = 'default'
    $vbLanguageVersion = 'default'
}


# Fill out the config entries for these code dom providers here. Using powershell to do
# this allows us to cache and restore customized attribute values from previous versions of
# this package in the upgrade scenario.
. "$PSScriptRoot\common.ps1"
$csCodeDomProvider = [CodeDomProviderDescription]@{
	TypeName="Microsoft.CodeDom.Providers.DotNetCompilerPlatform.CSharpCodeProvider";
	Assembly="Microsoft.CodeDom.Providers.DotNetCompilerPlatform";
    Version="3.4.0.0";
    FileExtension=".cs";
    Parameters=@(
		[CompilerParameterDescription]@{ Name="language"; DefaultValue="c#;cs;csharp"; IsRequired=$true; IsProviderOption=$false  },
		[CompilerParameterDescription]@{ Name="warningLevel"; DefaultValue="4"; IsRequired=$true; IsProviderOption=$false  },
		[CompilerParameterDescription]@{ Name="goofyParam"; DefaultValue="foobaz"; IsRequired=$true; IsProviderOption=$true  },
		[CompilerParameterDescription]@{ Name="verySeriousParam"; DefaultValue="synergy"; IsRequired=$true; IsProviderOption=$true  },
		[CompilerParameterDescription]@{ Name="compilerOptions"; DefaultValue="/langversion:" + $csLanguageVersion + " /nowarn:1659;1699;1701;612;618"; IsRequired=$false; IsProviderOption=$false  });
}
InstallCodeDomProvider $csCodeDomProvider
$vbCodeDomProvider = [CodeDomProviderDescription]@{
	TypeName="Microsoft.CodeDom.Providers.DotNetCompilerPlatform.VBCodeProvider";
	Assembly="Microsoft.CodeDom.Providers.DotNetCompilerPlatform";
    Version="3.4.0.0";
    FileExtension=".vb";
    Parameters=@(
		[CompilerParameterDescription]@{ Name="language"; DefaultValue="vb;vbs;visualbasic;vbscript"; IsRequired=$true; IsProviderOption=$false  },
		[CompilerParameterDescription]@{ Name="warningLevel"; DefaultValue="4"; IsRequired=$true; IsProviderOption=$false  },
		[CompilerParameterDescription]@{ Name="compilerOptions"; DefaultValue="/langversion:" + $vbLanguageVersion + " /nowarn:41008,40000,40008 /define:_MYTYPE=\&quot;Web\&quot; /optionInfer+"; IsRequired=$false; IsProviderOption=$false  });
}
InstallCodeDomProvider $vbCodeDomProvider


# We need to copy the provider assembly into the bin\ folder, otherwise
# Microsoft.VisualStudio.Web.Host.exe cannot find the assembly.
# However, users will see the error after they clean solutions.
New-Item $binDirectory -type directory -force | Out-Null
Copy-Item $libDirectory\* $binDirectory -force | Out-Null

# For Web Site, we need to copy the Roslyn toolset into
# the applicaiton's bin folder. 
# For Web Applicaiton project, this is done in csproj.
if ($project.Type -eq 'Web Site') {

    if ((Get-Item $compilerPackageDirectory) -isnot [System.IO.DirectoryInfo])
    {
        Write-Host "The install.ps1 cannot find the installation location of package $compilerPackageName, or the pakcage is not installed correctly."
        Write-Host 'The install.ps1 did not complete.'
        break
    }

    $roslynSubDirectory = Join-Path $binDirectory $roslynSubFolder
    New-Item $roslynSubDirectory -type directory -force | Out-Null
    Copy-Item $compilerPackageToolsDirectory\* $roslynSubDirectory -force | Out-Null

    # Generate a .refresh file for each dll/exe file.
    Push-Location
    Set-Location $projectRoot
    $relativeAssemblySource = Resolve-Path -relative $compilerPackageToolsDirectory
    Pop-Location

    Get-ChildItem -Path $roslynSubDirectory | `
    Foreach-Object {
        if  (($_.Extension -eq ".dll") -or ($_.Extension -eq ".exe")) {
            $refreshFile = $_.FullName
            $refreshFile += ".refresh"
            $refreshContent = Join-Path $relativeAssemblySource $_.Name    
            Set-Content $refreshFile $refreshContent
        }
    }
}