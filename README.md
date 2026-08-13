# Jupyter-PowerShellSDK

Jupyter kernel implementation for Windows PowerShell SDK and Windows PowerShell 5.

## Installation

A common modern approach is to download the install script directly from GitHub and execute it in place.

### PowerShell 5 kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
(Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShell5Kernel.ps1).Content | Invoke-Expression
```

By default, this installs both x64 and x86 kernels system-wide and will self-elevate to administrator if needed.

To install to the current user's area without administrator privileges, use `-User`:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShell5Kernel.ps1).Content)) -User
```

If you need to pass other arguments such as `-X64` or `-X86`, save the script locally first and then run it with parameters.

### PowerShell SDK kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
(Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShellSDKKernel.ps1).Content | Invoke-Expression
```

The script checks for .NET 10 first and installs the runtime automatically if it is missing.
It uses `winget` when available and falls back to a web download when it is not.
Without `-User` the script will self-elevate to administrator.

To install to the current user's area without administrator privileges, use `-User`.
Note: in user mode, .NET 10 Runtime installation is skipped — install it manually first if needed.

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShellSDKKernel.ps1).Content)) -User
```

## Uninstallation

You can also download and run the uninstall mode directly from GitHub.
Uninstall mode checks **both user-scope and system-scope** locations and removes any matching kernels found.

### PowerShell 5 kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShell5Kernel.ps1).Content)) -Uninstall
```

### PowerShell SDK kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
& ([scriptblock]::Create((Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShellSDKKernel.ps1).Content)) -Uninstall
```

## Notes

- Jupyter kernels are registered under the current Python environment.
- The SDK kernel requires .NET 10.
- The PowerShell 5 installer creates both x64 and x86 kernels unless a specific variant is selected.

## Third-Party Notices

This project uses third-party libraries including NetMQ, which is licensed under the GNU Lesser General Public License v3 (LGPL-3.0) with a special linking exception. See [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) for details.
