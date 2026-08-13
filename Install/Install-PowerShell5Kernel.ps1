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

.PARAMETER User
	Install into the current user's area only. No elevation is required.

.PARAMETER Uninstall
	Remove the installed kernels. Both user-scope and system-scope locations
	are checked and cleaned.

.NOTES
	If neither -X64 nor -X86 is specified, both variants are installed.
	Without -User the script self-elevates to administrator.

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -User

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -X64

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -X86

.EXAMPLE
	.\Install-PowerShell5Kernel.ps1 -Uninstall
#>
[CmdletBinding()]
param (
	[string]$WorkingFolder = '.',
	[switch]$X64,
	[switch]$X86,
	[switch]$User,
	[switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$WorkingFolder = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkingFolder)

if (-not $X64 -and -not $X86) {
	$X64 = $true
	$X86 = $true
}

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
	if ($X64)      { $argList += '-X64' }
	if ($X86)      { $argList += '-X86' }
	if ($Uninstall){ $argList += '-Uninstall' }
	if ($WorkingFolder -ne '.') { $argList += "-WorkingFolder `"$WorkingFolder`"" }

	$scriptPath = $PSCommandPath
	if ([string]::IsNullOrEmpty($scriptPath)) {
		$scriptPath = Join-Path $env:TEMP 'Install-PowerShell5Kernel_elevated.ps1'
		$MyInvocation.MyCommand.Definition | Set-Content -Path $scriptPath -Encoding UTF8
	}

	$psExe   = (Get-Process -Id $PID).Path
	$argFull = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" $($argList -join ' ')"
	Start-Process -FilePath $psExe -ArgumentList $argFull -Verb RunAs -Wait
	exit
}

# =====================================================================
# Resolve install paths based on scope
# =====================================================================
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
		Remove-TargetDirectory -Path (Join-Path $kp 'powershell5')     -Label 'PowerShell 5 kernelspec'
		Remove-TargetDirectory -Path (Join-Path $kp 'powershell5_x86') -Label 'PowerShell 5 (x86) kernelspec'
	}
	foreach ($pp in @($userPackagePath, $sysPackagePath)) {
		Remove-TargetDirectory -Path (Join-Path $pp 'powershell5_kernel')     -Label 'PowerShell 5 package folder'
		Remove-TargetDirectory -Path (Join-Path $pp 'powershell5_kernel_x86') -Label 'PowerShell 5 (x86) package folder'
	}

	Write-Host 'Uninstallation complete.'
	return
}

Write-Host "Fetching latest release information..."
$releaseURI    = 'https://github.com/sakaztk/Jupyter-PowerShellSDK/releases'
$latestRelease = (Invoke-WebRequest -Uri "$releaseURI/latest" -UseBasicParsing `
					-Headers @{ 'Accept' = 'application/json' } | ConvertFrom-Json).update_url
$versionString = $latestRelease -replace '.*tag/(.*)', '$1'
$links         = (Invoke-WebRequest -Uri "$releaseURI/expanded_assets/$versionString" -UseBasicParsing).Links.href

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

	Write-Host "Downloading $ZipName from $fileUri ..."
	try {
		Invoke-WebRequest -Uri $fileUri -UseBasicParsing -OutFile $zipPath
		Write-Host "Extracting to $InstallDir ..."
		Expand-Archive -Path $zipPath -DestinationPath $InstallDir -Force
	}
	finally {
		if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
	}

	$kernelSpecDir = Join-Path $KernelBasePath $KernelName
	New-Item -ItemType Directory -Path $kernelSpecDir -Force | Out-Null

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
Read-Host > $null
