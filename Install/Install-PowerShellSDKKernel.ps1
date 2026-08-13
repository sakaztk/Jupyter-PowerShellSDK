#Requires -Version 5.1
<#
.SYNOPSIS
	Installs the Jupyter PowerShell SDK Kernel (requires .NET 10).

.DESCRIPTION
	Checks whether .NET 10 Runtime or SDK is already installed.
	If neither is found, installs the Runtime automatically.
	winget is used if available; otherwise falls back to web download.

.PARAMETER WorkingFolder
	Temporary folder used for downloaded files. Defaults to the current directory.

.PARAMETER User
	Install into the current user's area only. No elevation is required.
	NOTE: .NET 10 Runtime installation is skipped in user mode (requires admin).

.PARAMETER Uninstall
	Remove the installed kernel. Both user-scope and system-scope locations
	are checked and cleaned.

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1 -User

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1 -WorkingFolder C:\Temp

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1 -Uninstall
#>
[CmdletBinding()]
param (
	[string]$WorkingFolder = '.',
	[switch]$User,
	[switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Resolve WorkingFolder to an absolute path up front
$WorkingFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkingFolder)

# =====================================================================
# Privilege check / self-elevation
# -User  : install to user scope, no elevation needed
# default: install to system scope; self-elevate if not already admin
# =====================================================================
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
	[Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $User -and -not $isAdmin) {
	Write-Host "Administrator privileges required. Re-launching as administrator..."

	$argList = @()
	if ($Uninstall) { $argList += '-Uninstall' }
	if ($WorkingFolder -ne '.') { $argList += "-WorkingFolder `"$WorkingFolder`"" }

	$scriptPath = $PSCommandPath
	if ([string]::IsNullOrEmpty($scriptPath)) {
		$scriptPath = Join-Path $env:TEMP 'Install-PowerShellSDKKernel_elevated.ps1'
		$MyInvocation.MyCommand.Definition | Set-Content -Path $scriptPath -Encoding UTF8
	}

	$psExe   = (Get-Process -Id $PID).Path
	$argFull = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $($argList -join ' ')"
	Start-Process -FilePath $psExe -ArgumentList $argFull -Verb RunAs -Wait
	exit
}

if ($User) {
	$packagePath = $(python -c "import site; print(site.getusersitepackages())")
	$kernelPath  = Join-Path (python -m jupyter --data-dir) 'kernels'
}
else {
	$packagePath = $(python -c "import site; print(site.getsitepackages()[0])")
	$kernelPath  = $((python -m jupyter kernelspec list | Select-String 'python3$' | ForEach-Object {($_ -replace '^\s+', '') -split '^python3\s+'})[1] | Split-Path)
}

"Scope        : $(if ($User) { 'User' } else { 'System' })"
"Package path : $packagePath"
"Kernel path  : $kernelPath"

if (-not (Test-Path $kernelPath)) {
	New-Item -ItemType Directory -Path $kernelPath -Force | Out-Null
}

function Remove-TargetDirectory {
	param (
		[string]$Path,
		[string]$Label
	)

	if (Test-Path $Path) {
		try {
			Remove-Item -Path $Path -Recurse -Force
			Write-Host "Removed ${Label}: $Path"
		}
		catch {
			Write-Warning "Could not remove ${Label} at $Path : $_"
		}
	}
	else {
		Write-Host "$Label not found: $Path"
	}
}

if ($Uninstall) {
	Write-Host "Uninstall mode selected. Checking both user and system locations..."

	$userPackagePath = $(python -c "import site; print(site.getusersitepackages())")
	$userKernelPath  = Join-Path (python -m jupyter --data-dir) 'kernels'
	$sysPackagePath  = $(python -c "import site; print(site.getsitepackages()[0])")
	$sysKernelPath   = $((python -m jupyter kernelspec list | Select-String 'python3$' | ForEach-Object {($_ -replace '^\s+', '') -split '^python3\s+'})[1] | Split-Path)

	foreach ($kp in @($userKernelPath, $sysKernelPath)) {
		Remove-TargetDirectory -Path (Join-Path $kp 'powershellSDK') -Label 'PowerShell SDK kernelspec'
	}
	foreach ($pp in @($userPackagePath, $sysPackagePath)) {
		Remove-TargetDirectory -Path (Join-Path $pp 'powershellSDK_kernel') -Label 'PowerShell SDK package folder'
	}

	Write-Host 'Uninstallation complete.'
	return
}

# Check .NET 10 installation and install Runtime if needed
function Test-DotNet10Installed {
	# Check via dotnet CLI
	try {
		$runtimes = & dotnet --list-runtimes 2>$null
		if ($runtimes -match 'Microsoft\.NETCore\.App 10\.') { return $true }
		$sdks = & dotnet --list-sdks 2>$null
		if ($sdks -match '^10\.') { return $true }
	}
	catch { }

	$regPaths = @(
		'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App',
		'HKLM:\SOFTWARE\dotnet\Setup\InstalledVersions\x64\sdk',
		'HKLM:\SOFTWARE\WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.NETCore.App'
	)
	foreach ($path in $regPaths) {
		if (Test-Path $path) {
			$versions = Get-Item $path | Select-Object -ExpandProperty Property -ErrorAction SilentlyContinue
			if ($versions -match '^10\.') { return $true }
		}
	}

	return $false
}

function Test-WingetAvailable {
	try {
		$null = & winget --version 2>$null
		return $true
	}
	catch { return $false }
}

function Install-DotNet10RuntimeByWinget {
	$package = 'Microsoft.DotNet.Runtime.10'
	$result  = winget list $package 2>$null
	if ($result -match [regex]::Escape($package)) {
		Write-Host "Upgrading $package ..."
		winget upgrade $package --accept-package-agreements --accept-source-agreements
	}
	else {
		Write-Host "Installing $package ..."
		winget install $package --accept-package-agreements --accept-source-agreements
	}
}

function Install-DotNet10RuntimeByWeb {
	param (
		[string]$TempFolder
	)

	Write-Host "Looking up latest .NET 10 Runtime installer..."
	$links     = (Invoke-WebRequest -Uri 'https://dotnet.microsoft.com/en-us/download/dotnet/10.0/runtime' -UseBasicParsing).Links.href
	$latestVer = ($links |
		Select-String -Pattern '.*runtime.*windows-x64-installer' |
		ForEach-Object { [version](($_ -replace '.*runtime-(([0-9]+\.){1}[0-9]+(\.[0-9]+)?)-.*', '$1')) } |
		Sort-Object -Descending |
		Select-Object -First 1
	).ToString()
	$latestUri = 'https://dotnet.microsoft.com' + ($links | Select-String -Pattern ".*runtime-$([regex]::Escape($latestVer))-windows-x64-installer" | Select-Object -First 1).ToString().Trim()
	$fileUri   = ((Invoke-WebRequest -Uri $latestUri -UseBasicParsing).Links.href | Select-String -Pattern '.*\.exe' | Select-Object -First 1).ToString().Trim()

	$dotnetInstaller = Join-Path $TempFolder 'dotnet.exe'
	Write-Host "Downloading .NET Runtime installer from $fileUri ..."
	Invoke-WebRequest -Uri $fileUri -UseBasicParsing -OutFile $dotnetInstaller
	Write-Host "Running .NET Runtime installer..."
	Start-Process -FilePath $dotnetInstaller -ArgumentList '/install /passive /norestart' -Wait
	Remove-Item $dotnetInstaller -Force -Verbose
}

Write-Host "Checking .NET 10 installation status..."
if (Test-DotNet10Installed) {
	Write-Host ".NET 10 Runtime or SDK is already installed. Skipping .NET installation."
}
else {
	Write-Host ".NET 10 not found. Installing Runtime..."
	try {
		if (Test-WingetAvailable) {
			Write-Host "winget is available. Using winget..."
			Install-DotNet10RuntimeByWinget
		}
		else {
			Write-Host "winget is not available. Falling back to web download..."
			Install-DotNet10RuntimeByWeb -TempFolder $WorkingFolder
		}
	}
	catch {
		Write-Warning "Error installing .NET 10 Runtime: $_"
	}
}

# Download PowerShell SDK Kernel archive
$zipName = 'PowerShellSDK.zip'
$zipPath = Join-Path $WorkingFolder $zipName

Write-Host "Fetching latest release information..."
$releaseApi    = 'https://api.github.com/repos/sakaztk/Jupyter-PowerShellSDK/releases/latest'
$latestRelease = Invoke-RestMethod -Uri $releaseApi -Headers @{ 'User-Agent' = 'Mozilla/5.0' }
if (-not $latestRelease.tag_name) {
	throw "Could not determine latest release tag from $releaseApi"
}
$versionString = $latestRelease.tag_name
$releaseURI    = 'https://github.com/sakaztk/Jupyter-PowerShellSDK/releases'
$links         = (Invoke-WebRequest -Uri "$releaseURI/expanded_assets/$versionString" -UseBasicParsing).Links.href
$fileLink      = $links | Select-String -Pattern 'Jupyter-PowerShellSDK-7.*\.zip|PowerShellSDK\.zip' | Select-Object -First 1
if (-not $fileLink) {
	throw "Could not locate PowerShellSDK zip asset in release assets for $versionString"
}
$fileUri       = 'https://github.com' + $fileLink.ToString().Trim()

Write-Host "Downloading $zipName from $fileUri ..."

# Install kernel binaries
$installDir = Join-Path $packagePath 'powershellSDK_kernel'
try {
	Invoke-WebRequest -Uri $fileUri -UseBasicParsing -OutFile $zipPath
	Write-Host "Extracting to $installDir ..."
	Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
}
finally {
	if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
}

# Create kernelspec directory
$kernelSpecDir = Join-Path $kernelPath 'powershellSDK'
New-Item -ItemType Directory -Path $kernelSpecDir -Force | Out-Null

# Download and resize logo
$logo64 = Join-Path $kernelSpecDir 'logo-64x64.png'
$logo32 = Join-Path $kernelSpecDir 'logo-32x32.png'
Write-Host "Downloading kernel logo..."
Invoke-WebRequest -UseBasicParsing `
	-Uri 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/Powershell_black_64.png' `
	-OutFile $logo64

Add-Type -AssemblyName System.Drawing
$image    = [System.Drawing.Image]::FromFile($logo64)
$bitmap32 = New-Object System.Drawing.Bitmap(32, 32)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap32)
$graphics.DrawImage($image, 0, 0, 32, 32)
$bitmap32.Save($logo32, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap32.Dispose()
$image.Dispose()

# Write kernel.json
$exePath = "$($installDir.Replace('\', '/'))/Jupyter_PowerShellSDK.exe"
$kernelJson = @"
{
	"argv": [
		"$exePath",
		"{connection_file}"
	],
	"display_name": "PowerShell 7 (SDK)",
	"language": "Powershell"
}
"@
[System.IO.File]::WriteAllText((Join-Path $kernelSpecDir 'kernel.json'), $kernelJson, (New-Object System.Text.UTF8Encoding($false)))

# Move any extra PNGs shipped with the archive
$extraPngs = Join-Path $installDir '*.png'
if (Test-Path $extraPngs) {
	Move-Item -Path $extraPngs -Destination $kernelSpecDir -Force
}

Write-Host "Installation complete."
Read-Host > $null
