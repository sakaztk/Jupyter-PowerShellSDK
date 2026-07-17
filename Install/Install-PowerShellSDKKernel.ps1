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

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1

.EXAMPLE
	.\Install-PowerShellSDKKernel.ps1 -WorkingFolder C:\Temp
#>
[CmdletBinding()]
param (
	[string]$WorkingFolder = '.',
	[switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Resolve WorkingFolder to an absolute path up front
$WorkingFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkingFolder)

# Resolve paths from Jupyter / Python
$packagePath = $(python -c "import site; print(site.getusersitepackages())")
$kernelPath  = $((python -m jupyter kernelspec list | Select-String 'python3$' | ForEach-Object {
	($_ -replace '^\s+', '') -split '^python3\s+'
})[1] | Split-Path)

if ([string]::IsNullOrEmpty($kernelPath)) {
	throw "Could not determine Jupyter kernel path. Is the python3 kernel registered?"
}

"Package path : $packagePath"
"Kernel path  : $kernelPath"

function Remove-TargetDirectory {
	param (
		[string]$Path,
		[string]$Label
	)

	if (Test-Path $Path) {
		Remove-Item -Path $Path -Recurse -Force
		Write-Host "Removed ${Label}: $Path"
	}
	else {
		Write-Host "$Label not found: $Path"
	}
}

if ($Uninstall) {
	Write-Host "Uninstall mode selected."
	Remove-TargetDirectory -Path (Join-Path $kernelPath 'powershellSDK') -Label 'PowerShell SDK kernelspec'
	Remove-TargetDirectory -Path (Join-Path $packagePath 'powershellSDK_kernel') -Label 'PowerShell SDK package folder'
	Write-Host 'Uninstallation complete.'
	return
}

# =====================================================================
# 1. Check .NET 10 installation and install Runtime if needed
# =====================================================================
function Test-DotNet10Installed {
	# Check via dotnet CLI
	try {
		$runtimes = & dotnet --list-runtimes 2>$null
		if ($runtimes -match 'Microsoft\.NETCore\.App 10\.') { return $true }
		$sdks = & dotnet --list-sdks 2>$null
		if ($sdks -match '^10\.') { return $true }
	}
	catch { }

	# Check registry as fallback
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

# =====================================================================
# 2. Download PowerShell SDK Kernel archive
# =====================================================================
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

# =====================================================================
# 3. Install kernel binaries
# =====================================================================
$installDir = Join-Path $packagePath 'powershellSDK_kernel'
try {
	Invoke-WebRequest -Uri $fileUri -UseBasicParsing -OutFile $zipPath
	Write-Host "Extracting to $installDir ..."
	Expand-Archive -Path $zipPath -DestinationPath $installDir -Force
}
finally {
	if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
}

# =====================================================================
# 4. Create kernelspec directory
# =====================================================================
$kernelSpecDir = Join-Path $kernelPath 'powershellSDK'
New-Item -ItemType Directory -Path $kernelSpecDir -Force | Out-Null

# --- Download and resize logo ---
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

# --- Write kernel.json ---
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
