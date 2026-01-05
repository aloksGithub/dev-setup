# Windows Development Environment Setup Script
#
# This script installs a set of common development tools on a fresh Windows machine.
# It uses the winget package manager, which is included in modern versions of Windows.
#
# To run this script:
# 1. Open PowerShell as an Administrator.
# 2. Navigate to the directory where you saved this script.
# 3. If you get an error about scripts being disabled on your system, run:
#    Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
# 4. Run the script: .\install_dev_tools.ps1

# --- Configuration: Add or remove tools here ---
# VM Configuration
$vmConfig = @{
    MemoryMB = 8192
    Cpus = 4
    DiskSizeMB = 32768
}

$packages = @(
    @{id="Rustlang.Rustup"; name="Rust (via rustup)"},
    @{id="Git.Git"; name="Git"},
    @{id="Oracle.VirtualBox"; name="VirtualBox"},
    @{id="Docker.DockerDesktop"; name="Docker Desktop"},
    @{id="CoreyButler.NVMforWindows"; name="NVM for Windows"},
    @{id="Mozilla.Firefox"; name="Firefox"},
    @{id="Anysphere.Cursor"; name="Cursor AI Editor"},
    @{id="Surfshark.Surfshark"; name="Surfshark"},
    @{id="Valve.Steam"; name="Steam"},
    @{id="Microsoft.VisualStudio.2022.BuildTools"; name="Visual Studio 2022 Build Tools (C++ and Windows 10 SDK 19041)"; override='--quiet --wait --norestart --nocache --add Microsoft.VisualStudio.Component.VC.Tools.x86.x64 --add Microsoft.VisualStudio.Component.Windows10SDK.19041'}
)

# --- Helper Functions ---
function Refresh-Environment {
    Write-Host "Refreshing environment variables from registry..." -ForegroundColor Cyan
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Install-WingetPackage {
    param (
        [Parameter(Mandatory=$true)] $Package
    )

    Write-Host "Installing $($Package.name)..." -ForegroundColor Cyan
    
    # Check if package is already installed
    winget list --id $Package.id -n 1 --accept-source-agreements | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "$($Package.name) is already installed. Skipping." -ForegroundColor Green
        return
    }

    $args = @("install", "-e", "--id", $Package.id, "--accept-source-agreements", "--accept-package-agreements")
    if ($Package.ContainsKey('override') -and $Package.override) {
        $args += "--override"
        $args += $Package.override
    }

    Write-Host "Running: winget $args"
    
    $maxRetries = 5
    $retryCount = 0
    $installed = $false

    while (-not $installed -and $retryCount -lt $maxRetries) {
        & winget $args
        
        if ($LASTEXITCODE -eq 0) {
            $installed = $true
            Write-Host "$($Package.name) installed successfully." -ForegroundColor Green
        } elseif ($LASTEXITCODE -eq 1618) {
            # 1618 = ERROR_INSTALL_ALREADY_RUNNING
            $retryCount++
            Write-Warning "Another installation is in progress (Exit code 1618). Retrying in 15 seconds... ($retryCount/$maxRetries)"
            Start-Sleep -Seconds 15
        } else {
            # Fatal error, stop retrying
            Write-Host "Failed to install $($Package.name) with exit code $LASTEXITCODE." -ForegroundColor Red
            break
        }
    }

    if (-not $installed -and $retryCount -eq $maxRetries) {
        Write-Host "Failed to install $($Package.name) after $maxRetries retries (Install in progress)." -ForegroundColor Red
    }
}


# --- Main Script ---

Write-Host "Starting development environment setup..." -ForegroundColor Green

# --- WSL and Docker ---
Write-Host "Checking for Docker prerequisites (WSL 2)..." -ForegroundColor Cyan
$wsl_feature = "Microsoft-Windows-Subsystem-Linux"
$vm_platform_feature = "VirtualMachinePlatform"

$wsl_status = Get-WindowsOptionalFeature -Online -FeatureName $wsl_feature
if (-not $wsl_status.State -eq 'Enabled') {
    Write-Host "Windows Subsystem for Linux (WSL) is not enabled. It is required for Docker Desktop."
    Write-Host "This script can enable it for you, which will require a system restart."
    $choice = Read-Host "Do you want to enable WSL and Virtual Machine Platform? (y/n)"
    if ($choice -eq 'y') {
        Write-Host "Enabling WSL and Virtual Machine Platform..."
        dism.exe /online /enable-feature /featurename:$wsl_feature /all /norestart
        dism.exe /online /enable-feature /featurename:$vm_platform_feature /all /norestart
        Write-Host "WSL and Virtual Machine Platform have been enabled." -ForegroundColor Green
        Write-Host "A RESTART IS REQUIRED for these changes to take effect." -ForegroundColor Yellow
        Write-Host "After restarting, you may need to install a Linux distribution from the Microsoft Store (e.g., Ubuntu)."
        Write-Host "Then, open PowerShell and run 'wsl --set-default-version 2' to set WSL 2 as the default."
        Write-Host "Please restart your computer and then re-run this script to install Docker and other tools."
        exit
    } else {
        Write-Host "Skipping WSL setup. Docker Desktop installation will be skipped." -ForegroundColor Yellow
    }
} else {
    Write-Host "WSL seems to be enabled." -ForegroundColor Green
}


# --- Set WSL 2 as default ---
Write-Host "Attempting to set WSL 2 as the default version..." -ForegroundColor Cyan

# Proactively update WSL to prevent "Class not registered" / corruption errors
Write-Host "Checking for WSL updates..."
wsl --update
if ($LASTEXITCODE -eq 0) {
    Write-Host "WSL update check completed." -ForegroundColor Green
}

try {
    wsl --set-default-version 2
    Write-Host "WSL 2 has been set as the default version." -ForegroundColor Green
} catch {
    Write-Warning "Failed to set WSL 2 as default. This is often because the WSL kernel is not installed."
    $choice = Read-Host "Do you want this script to run 'wsl --update' for you? (y/n)"
    if ($choice -eq 'y') {
        Write-Host "Running 'wsl --update'..."
        wsl --update --web-download
        if ($LASTEXITCODE -eq 0) {
            Write-Host "WSL update completed. The script will now try to set WSL 2 as the default version again." -ForegroundColor Green
            Write-Host "If the update requires a restart, please do so and then re-run this script." -ForegroundColor Yellow
            try {
                wsl --set-default-version 2
                Write-Host "Successfully set WSL 2 as the default version after the update." -ForegroundColor Green
            } catch {
                Write-Warning "Still failed to set WSL 2 as default after update. A restart is likely required."
                Write-Warning "Please restart your computer and then re-run this script."
                exit
            }
        } else {
            Write-Warning "Failed to run 'wsl --update'. Please run it manually from an Administrator PowerShell."
            Write-Warning "You can download the kernel manually from: https://aka.ms/wsl2kernel"
        }
    } else {
        Write-Warning "Skipping WSL kernel update. Docker Desktop installation will likely fail."
    }
}


# --- Install Packages ---
foreach ($pkg in $packages) {
    # Docker has a dependency on WSL, so we check again.
    if ($pkg.id -eq "Docker.DockerDesktop") {
        $wsl_status_check = Get-WindowsOptionalFeature -Online -FeatureName "Microsoft-Windows-Subsystem-Linux"
        if (-not $wsl_status_check.State -eq 'Enabled') {
            Write-Host "Cannot install Docker Desktop because WSL is not enabled. Please enable it and restart." -ForegroundColor Red
            continue
        }
    }
    
    Install-WingetPackage -Package $pkg
}

# Try to make new tools available in the current session
Refresh-Environment

# --- Automated Post-installation Actions ---
Write-Host "Running automated post-installation steps..." -ForegroundColor Cyan

# 1. Update Rust toolchain via rustup
$rutool = Join-Path $env:USERPROFILE ".cargo\bin\rustup.exe"
if (Test-Path $rutool) {
    Write-Host "Updating Rust toolchain (rustup update)..." -ForegroundColor Cyan
    & $rutool update stable
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Rust toolchain updated." -ForegroundColor Green
    } else {
        Write-Warning "rustup update failed. You can run it manually later."
    }
} else {
    Write-Warning "rustup.exe not found. Rust might not have installed correctly or a restart is required before it is available in PATH."
}

# 2. Install latest Node.js via nvm-windows
$nvmCmd = Get-Command "nvm.exe" -ErrorAction SilentlyContinue

if ($nvmCmd) {
    Write-Host "Installing latest Node.js via nvm-windows..." -ForegroundColor Cyan
    & nvm install latest
    if ($LASTEXITCODE -eq 0) {
        & nvm use latest
        Write-Host "Latest Node.js installed and activated." -ForegroundColor Green
    } else {
        Write-Warning "nvm failed to install Node.js. You can run 'nvm install lts' manually later."
    }
} else {
    Write-Warning "nvm.exe not found even after environment refresh. NVM for Windows may require a system logoff/logon before it is available in PATH."
}

# 3. Install pyenv-win for managing multiple Python versions
if (-not (Get-Command pyenv -ErrorAction SilentlyContinue)) {
    Write-Host "Installing pyenv-win (Python version manager)…" -ForegroundColor Cyan
    $pyenvScript = Join-Path $env:TEMP "install-pyenv-win.ps1"
    Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/pyenv-win/pyenv-win/master/pyenv-win/install-pyenv-win.ps1" -OutFile $pyenvScript
    & $pyenvScript
    if ($LASTEXITCODE -eq 0) {
        # Update current session PATH so pyenv is immediately usable
        $pyenvBin   = Join-Path $env:USERPROFILE ".pyenv\pyenv-win\bin"
        $pyenvShims = Join-Path $env:USERPROFILE ".pyenv\pyenv-win\shims"
        if (-not ($env:PATH -like "*$pyenvBin*")) {
            $env:PATH = "$pyenvBin;$pyenvShims;$env:PATH"
        }
        Write-Host "pyenv-win installed and PATH updated. Version: $(pyenv --version)" -ForegroundColor Green
    } else {
        Write-Warning "pyenv-win installer exited with code $LASTEXITCODE. You may need to run the installer manually."
    }
} else {
    Write-Host "pyenv-win already present. Skipping installation." -ForegroundColor Green
}

# 3b. Install the latest available Python version using pyenv-win
$pyenvCmd = Get-Command pyenv -ErrorAction SilentlyContinue
if ($pyenvCmd) {
    Write-Host "Installing latest stable Python 3 via pyenv-win…" -ForegroundColor Cyan
    & pyenv install 3
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Setting Python 3 as the global default…" -ForegroundColor Cyan
        & pyenv global 3
        Write-Host "Active Python version is now: $(python --version)" -ForegroundColor Green
    } else {
        Write-Warning "Failed to install Python 3 via pyenv. You can try manually with 'pyenv install 3'."
    }
} else {
    Write-Warning "pyenv command not found in PATH; skipping automatic Python installation."
}

# 4. Download Ubuntu 24.04 LTS ISO for VirtualBox
Write-Host "Checking for Ubuntu 24.04 LTS ISO..." -ForegroundColor Cyan
try {
    $isoUrl = "https://releases.ubuntu.com/24.04/ubuntu-24.04.1-desktop-amd64.iso"
    $isoFilename = "ubuntu-24.04.1-desktop-amd64.iso"
    $downloadPath = Join-Path $env:USERPROFILE "Downloads\$isoFilename"

    if (-not (Test-Path $downloadPath)) {
        Write-Host "Downloading Ubuntu 24.04 LTS ISO from $isoUrl ..."
        
        # Use BITS for faster, more reliable downloads
        Start-BitsTransfer -Source $isoUrl -Destination $downloadPath -DisplayName "Downloading Ubuntu ISO"
        
        Write-Host "Ubuntu ISO downloaded to $downloadPath" -ForegroundColor Green
    } else {
        Write-Host "Ubuntu ISO already exists at $downloadPath . Skipping download." -ForegroundColor Green
    }
} catch {
    Write-Warning "Failed to download Ubuntu ISO: $_.Exception.Message"
    Write-Warning "You can download it manually from https://ubuntu.com/download/desktop"
}

# --- Create an isolated Ubuntu VM using VirtualBox unattended install ---
$vboxManage = Join-Path ${env:ProgramFiles} "Oracle\VirtualBox\VBoxManage.exe"
if (-not (Test-Path $vboxManage)) {
    Write-Warning "VBoxManage.exe not found. Ensure VirtualBox is installed and then re-run the script to create VMs."
} elseif (-not (Test-Path $downloadPath)) {
    Write-Warning "Ubuntu ISO not available. Skipping VM creation."
} else {
    $vmName = "UbuntuVM"
    Write-Host "\n--- Creating $vmName ---" -ForegroundColor Cyan
    
    # Prompt for a secure password
    Write-Host "Please enter a password for the 'ubuntu' user in the VM." -ForegroundColor Yellow
    Write-Host "This password will be required to log in and run sudo commands." -ForegroundColor Yellow
    $vmPasswordSecure = Read-Host -Prompt "Enter password" -AsSecureString
    $vmPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($vmPasswordSecure))
    
    if ([string]::IsNullOrWhiteSpace($vmPassword)) {
        Write-Warning "Password cannot be empty. Exiting."
        exit
    }

    # Only proceed if VM doesn't exist (or was deleted)
    $exists = & $vboxManage list vms | Select-String -Pattern $vmName -SimpleMatch -Quiet
    if (-not $exists) {
        # Create the VM container
        & $vboxManage createvm --name $vmName --ostype Ubuntu_64 --register
        
        # Configure basic resources and isolation settings using variables
        # VRAM 128MB and USB Tablet are critical for modern Ubuntu desktop experience
        & $vboxManage modifyvm $vmName --memory $vmConfig.MemoryMB --cpus $vmConfig.Cpus --graphicscontroller vmsvga --vram 128 --mouse usbtablet --nic1 nat --clipboard disabled --draganddrop disabled
        
        # Unattended installation (VirtualBox 7+)
        Write-Host "Starting unattended installation for $vmName ..." -ForegroundColor Cyan
        & $vboxManage createmedium disk --filename "$vmName.vdi" --size $vmConfig.DiskSizeMB
        & $vboxManage storagectl  $vmName --name "SATA" --add sata --controller IntelAhci
        & $vboxManage storageattach $vmName --storagectl "SATA" --port 0 --device 0 --type hdd --medium "$vmName.vdi"
        & $vboxManage unattended install $vmName `
            --user ubuntu --password $vmPassword `
            --full-user-name "Ubuntu User" `
            --hostname "${vmName}.local" `
            --iso $downloadPath `
            --locale en_US `
            --time-zone UTC `
            --start-vm=gui `
            --post-install-command `
              "apt-get update && \
               DEBIAN_FRONTEND=noninteractive apt-get -y install ubuntu-desktop \
               virtualbox-guest-utils virtualbox-guest-x11"

        if ($LASTEXITCODE -eq 0) {
            Write-Host "$vmName creation started." -ForegroundColor Green
            Write-Host "You can login with the password you provided once the install completes." -ForegroundColor Green
        } else {
            Write-Warning "Failed to start unattended install for $vmName. You can try manual creation later via VirtualBox GUI."
        }
    }
}

# --- Final message ---
Write-Host "--------------------------------------------------" -ForegroundColor Green
Write-Host "Automation complete. Rust toolchain, Node.js, Ubuntu ISO download, and VM creation steps have executed." -ForegroundColor Green
Write-Host "If Ubuntu VMs are still installing, monitor them with 'VBoxManage list runningvms'." -ForegroundColor Yellow