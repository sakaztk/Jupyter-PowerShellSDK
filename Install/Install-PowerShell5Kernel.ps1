#Requires -Version 5.1
<#
.SYNOPSIS
	Installs the Jupyter PowerShell 5 Kernel.

.PARAMETER WorkingFolder
	Temporary folder used for downloaded files. Defaults to the current directory.

.PARAMETER X64
	If specified, installs only the x64 variant.

.PARAMETER X86
	If specified, installs only the x86 (32-bit) variant.

.NOTES
	If neither -X64 nor -X86 is specified, both variants are installed.

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -X64

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -X86

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -X64 -X86
#>
[CmdletBinding()]
param (
	[string]$WorkingFolder = '.',
	[switch]$X64,
	[switch]$X86,
	[switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Resolve WorkingFolder to an absolute path up front
$WorkingFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkingFolder)

# If neither switch is specified, install both
if (-not $X64 -and -not $X86) {
	$X64 = $true
	$X86 = $true
}

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
	Remove-TargetDirectory -Path (Join-Path $kernelPath 'powershell5') -Label 'PowerShell 5 kernelspec'
	Remove-TargetDirectory -Path (Join-Path $kernelPath 'powershell5_x86') -Label 'PowerShell 5 (x86) kernelspec'
	Remove-TargetDirectory -Path (Join-Path $packagePath 'powershell5_kernel') -Label 'PowerShell 5 package folder'
	Remove-TargetDirectory -Path (Join-Path $packagePath 'powershell5_kernel_x86') -Label 'PowerShell 5 (x86) package folder'
	Write-Host 'Uninstallation complete.'
	return
}

# Fetch release info once
Write-Host "Fetching latest release information..."
$releaseURI    = 'https://github.com/sakaztk/Jupyter-PowerShellSDK/releases'
$latestRelease = (Invoke-WebRequest -Uri "$releaseURI/latest" -UseBasicParsing `
					-Headers @{ 'Accept' = 'application/json' } | ConvertFrom-Json).update_url
$versionString = $latestRelease -replace '.*tag/(.*)', '$1'
$links         = (Invoke-WebRequest -Uri "$releaseURI/expanded_assets/$versionString" -UseBasicParsing).Links.href

# Shared logo URI (same image for x64 and x86)
$logoUri   = 'https://raw.githubusercontent.com/PowerShell/PowerShell/master/assets/Powershell_64.png'
$logoCache = $null  # path to a downloaded copy; reused on second call

function Install-PS5Kernel {
	param (
		[string]$ZipName,
		[string]$KernelName,
		[string]$DisplayName,
		[string]$InstallDir,
		[string[]]$ReleaseLinks,
		[string]$KernelBasePath,
		[string]$TempFolder
	)

	$zipPath = Join-Path $TempFolder $ZipName
	$fileUri = 'https://github.com' + ($ReleaseLinks | Select-String -Pattern ".*$([regex]::Escape($ZipName))" | Select-Object -First 1).ToString().Trim()

	# --- Download and extract release archive ---
	Write-Host "Downloading $ZipName from $fileUri ..."
	try {
		Invoke-WebRequest -Uri $fileUri -UseBasicParsing -OutFile $zipPath
		Write-Host "Extracting to $InstallDir ..."
		Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
	}
	finally {
		if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
	}

	# --- Create kernelspec directory ---
	$kernelSpecDir = Join-Path $KernelBasePath $KernelName
	New-Item -ItemType Directory -Path $kernelSpecDir -Force | Out-Null

	# --- Download logo (reuse cached copy on second call) ---
	$logo64 = Join-Path $kernelSpecDir 'logo-64x64.png'
	$logo32 = Join-Path $kernelSpecDir 'logo-32x32.png'

	if ($null -ne $script:logoCache -and (Test-Path $script:logoCache)) {
		Copy-Item -Path $script:logoCache -Destination $logo64 -Force
	}
	else {
		Write-Host "Downloading kernel logo..."
		Invoke-WebRequest -Uri $script:logoUri -UseBasicParsing -OutFile $logo64
		$script:logoCache = $logo64
	}

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
	$exePath = "$($InstallDir.Replace('\', '/'))/Jupyter_PowerShell5.exe"
	$kernelJson = @"
{
	"argv": [
		"$exePath",
		"{connection_file}"
	],
	"display_name": "$DisplayName",
	"language": "Powershell"
}
"@
	[System.IO.File]::WriteAllText((Join-Path $kernelSpecDir 'kernel.json'), $kernelJson, (New-Object System.Text.UTF8Encoding($false)))

	# Move any extra PNGs shipped with the archive
	$extraPngs = Join-Path $InstallDir '*.png'
	if (Test-Path $extraPngs) {
		Move-Item -Path $extraPngs -Destination $kernelSpecDir -Force
	}

	Write-Host "$DisplayName kernel installed successfully."
}

if ($X64) {
	Install-PS5Kernel `
		-ZipName       'PowerShell5.zip' `
		-KernelName    'powershell5' `
		-DisplayName   'PowerShell 5' `
		-InstallDir    (Join-Path $packagePath 'powershell5_kernel') `
		-ReleaseLinks  $links `
		-KernelBasePath $kernelPath `
		-TempFolder    $WorkingFolder
}

if ($X86) {
	Install-PS5Kernel `
		-ZipName       'PowerShell5_x86.zip' `
		-KernelName    'powershell5_x86' `
		-DisplayName   'PowerShell 5 (x86)' `
		-InstallDir    (Join-Path $packagePath 'powershell5_kernel_x86') `
		-ReleaseLinks  $links `
		-KernelBasePath $kernelPath `
		-TempFolder    $WorkingFolder
}

Write-Host "Installation complete."
