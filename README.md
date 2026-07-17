# Jupyter-PowerShellSDK

Jupyter kernel implementation for Windows PowerShell SDK and Windows PowerShell 5.

## Installation

A common modern approach is to download the install script directly from GitHub and execute it in place.

### PowerShell 5 kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
(Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShell5Kernel.ps1).Content | Invoke-Expression
```

By default, this installs both x64 and x86 kernels.

If you need to pass arguments such as `-X64` or `-X86`, save the script locally first and then run it with parameters.

### PowerShell SDK kernel

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope process
(Invoke-WebRequest -UseBasicParsing -Uri https://raw.githubusercontent.com/sakaztk/Jupyter-PowerShellSDK/powershellsdk/Install/Install-PowerShellSDKKernel.ps1).Content | Invoke-Expression
```

The script checks for .NET 10 first and installs the runtime automatically if it is missing.
It uses `winget` when available and falls back to a web download when it is not.

## Uninstallation

You can also download and run the uninstall mode directly from GitHub.

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
