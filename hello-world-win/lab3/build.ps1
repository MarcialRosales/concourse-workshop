Param (
    [string] $mode,
	[string] $targetFramework
)

Set-Variable -Option Constant -Name DefaultFramework     -Value "4.0.0.0"
Set-Variable -Option Constant -Name DefaultFrameworkPath -Value "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\"
Set-Variable -Option Constant -Name MsBuildApp           -Value "$DefaultFrameworkPath\MSBuild.exe"

# Write a nice banner for the peoples.
function Write-Banner {
    . {
        Clear-Host
        # Detect the .net frameworks on the build server.
		Write-Host "Detecting .Net Versions" -ForegroundColor Gray
        #Detect-Frameworks
        
         # Show the parameters
        
    } | Out-Null          
}

# Get the current mode
function Get-Mode {
    . {
        if ($mode -eq '') {
            $mode = 'build'
        }

    } | Out-Null

    return $mode
}

# The main entry point for this application.
function main {
    Write-Banner
    $buildConfig = if ($(Get-Mode) -eq 'test') {'Test'} Else {'Release'}

    Write-Host "Building application with $(Get-Mode) mode " -ForegroundColor Green
}

main # Run the application.