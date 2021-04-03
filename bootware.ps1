# If unable to execute due to policy rules, run 
# Set-ExecutionPolicy RemoteSigned -Scope CurrentUser.


# Show CLI help information.
Function Usage() {
    Switch ($Args[0]) {
        "bootstrap" {
            Write-Output @'
Bootware bootstrap
Boostrap install computer software

USAGE:
    bootware bootstrap [OPTIONS]

OPTIONS:
    -c, --config <PATH>             Path to bootware user configuation file
    -d, --dev                       Run bootstrapping in development mode
    -h, --help                      Print help information
        --no-passwd                 Do not ask for user password
        --no-setup                  Skip Bootware dependency installation
    -p, --playbook <FILE-NAME>      Name of play to execute
    -s, --skip <TAG-LIST>           Ansible playbook tags to skip
    -t, --tags <TAG-LIST>           Ansible playbook tags to select
    -u, --url <URL>                 URL of playbook repository
'@
        }
        "config" { 
            Write-Output @'
Bootware config
Download default Bootware configuration file

USAGE:
    bootware config [OPTIONS]

OPTIONS:
    -d, --dest <PATH>       Path to alternate download destination
    -e, --empty             Write empty configuration file
    -h, --help              Print help information
    -s, --source <URL>      URL to configuration file
'@      
        }
        "main" {
            Write-Output @'
Bootware 0.3.0
Boostrapping software installer

USAGE:
    bootware [OPTIONS] [SUBCOMMAND]

OPTIONS:
    -h, --help       Print help information
    -v, --version    Print version information

SUBCOMMANDS:
    bootstrap        Boostrap install computer software
    config           Generate default Bootware configuration file
    setup            Install dependencies for Bootware
    update           Update Bootware to latest version
'@
        }
        "setup" {
            Write-Output @'
Bootware setup
Install dependencies for Bootware

USAGE:
    bootware setup [OPTIONS]

OPTIONS:
    -h, --help      Print help information
    --no-wsl        Do not configure WSL
'@
        }
        "update" {
            Write-Output @'
Bootware update
Update Bootware to latest version

USAGE:
    bootware update [FLAGS]

FLAGS:
    -h, --help                  Print help information
    -v, --version <VERSION>     Version override for update
'@
        }
    }
}

# Subcommand to bootstrap software installations.
Function Bootstrap() {
    $ArgIdx = 0
    $Cmd = "pull"
    $NoSetup = 0
    $Playbook = "main.yaml"
    $Runner = "docker"
    $URL = "https://github.com/wolfgangwazzlestrauss/bootware.git"
    $UsePasswd = 1
    $UsePlaybook = 0
    $UsePull = 1

    ForEach ($Arg in $Args) {
        Switch ($Arg) {
            {$_ -In "-c", "--config"} {
                $ConfigPath = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
            {$_ -In "-d", "--dev"} {
                $Cmd = "playbook"
                $UsePlaybook = 1
                $UsePull = 0
                $ArgIdx += 1
            }
            {$_ -In "-h", "--help"} {
                Usage "bootstrap"
                Exit 0
            }
             "--no-passwd" {
                $UsePasswd = 0
                $ArgIdx += 1
            }
            {$_ -In "-p", "--playbook"} {
                $Playbook = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
            {$_ -In "-s", "--skip"} {
                $Skip = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
            {$_ -In "-t", "--tags"} {
                $Tags = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
            {$_ -In "-u", "--url"} {
                $URL = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
        }
    }

    Setup

    # Find IP address of Windows host relative from WSL. Taken from
    # https://github.com/Microsoft/WSL/issues/1032#issuecomment-677727024.
    $IPAddress = $(wsl cat /etc/resolv.conf `| grep nameserver `| cut -d ' ' -f 2)

    $Playbook = "$RepoPath/main.yaml" -Replace "\\","/" -Replace "C:","/mnt/c"
    wsl bootware bootstrap --winrm --inventory "$IPAddress," --playbook "$Playbook" --user "$Env:UserName"
}

# Subcommand to generate or download Bootware configuration file.
Function Config() {
    $ArgIdx = 0
    $SrcURL = "https://raw.githubusercontent.com/wolfgangwazzlestrauss/bootware/master/host_vars/bootware.yaml"
    $DstFile = "$HOME/.bootware/config.yaml"
    $EmptyCfg =0

    ForEach ($Arg in $Args) {
        Switch ($Arg) {
            {$_ -In "-d", "--dest"} {
                $DstFile = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
            {$_ -In "-e", "--empty"} {
                $ArgIdx += 1
                $EmptyCfg = 1
            }
            {$_ -In "-h", "--help"} {
                Usage "config"
                Exit 0
            }
            {$_ -In "-s", "--source"} {
                $SrcURL = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
        }
    }

    New-Item -Force -ItemType Directory -Path $(Split-Path -Path $DstFile -Parent) | Out-Null

    If ($EmptyCfg) {
        Write-Output "Writing empty configuration file to $DstFile..."
        Write-Output "passwordless_sudo: false" > "$DstFile"
    } Else {
        Write-Output "Downloading configuration file to $DstFile..."
        DownloadFile "$SrcURL" "$DstFile"
    }
}

# Downloads file to destination efficiently.
Function DownloadFile($SrcURL, $DstFile) {
    # The progress bar updates every byte, which makes downloads slow. See
    # https://stackoverflow.com/a/43477248 for an explanation.
    $ProgressPreference = "SilentlyContinue"
    Invoke-WebRequest -UseBasicParsing -Uri "$SrcURL" -OutFile "$DstFile"
}

# Print error message and exit script with error code.
Function Error($Message) {
    Write-Error "Error: $Message"
    Exit 1
}

# Find path of Bootware configuation file.
Function FindConfigPath($FilePath) {
    If (Test-Path -Path "$1" -PathType Leaf) {
        $ConfigPath = $FilePath
    } ElseIf (Test-Path -Path "$(Get-Location)/bootware.yaml" -PathType Leaf) {
        $ConfigPath = "$(Get-Location)/bootware.yaml"
    } ElseIf (Test-Path Env:BOOTWARE_CONFIG) {
        $ConfigPath = "$Env:BOOTWARE_CONFIG"
    } ElseIf (Test-Path -Path "$HOME/.bootware/config.yaml" -PathType Leaf) {
        $ConfigPath = "$HOME/.bootware/config.yaml"
    } else {
        Write-Output "Unable to find Bootware configuation file."
        Config --empty
        $ConfigPath = "$HOME/.bootware/config.yaml"
    }

    Write-Output "Using $ConfigPath as configuration file."
}

# Subcommand to configure boostrapping services and utilities.
Function Setup() {
    $WSL = 1

    ForEach ($Arg in $Args) {
        Switch ($Arg) {
            {$_ -In "-h", "--help"} {
                Usage "setup"
                Exit 0
            }
            "--no-wsl" {
                $WSL = 0
                $ArgIdx += 1
            }
        }
    }

    # Install Chocolatey package manager.
    If (-Not (Get-Command choco -ErrorAction SilentlyContinue)) {
        Write-Output "Downloading Chocolatey package manager..."

        # The progress bar updates every byte, which makes downloads slow. See
        # https://stackoverflow.com/a/43477248 for an explanation.
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -UseBasicParsing -Uri "https://chocolatey.org/install.ps1" | Invoke-Expression

        # Several packages require the Visual C++ build tools and Chocolatey
        # requires user interaction yes prompt.
        Write-Output "Installing Visual C++ build tools..."
        choco install -y microsoft-visual-cpp-build-tools
    }

    # Install Scoop package manager.
    If (-Not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Write-Output "Downloading Scoop package manager..."

        # The progress bar updates every byte, which makes downloads slow. See
        # https://stackoverflow.com/a/43477248 for an explanation.
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -UseBasicParsing -Uri "https://get.scoop.sh" | Invoke-Expression
    }

     # Git is required for addding Scoop buckets.
    If (-Not (Get-Command git -ErrorAction SilentlyContinue)) {
        scoop install git
    }
    
    $ScoopBuckets = $(scoop bucket list)
    ForEach ($Bucket in @("extras", "main", "nerd-fonts", "versions")) {
        If ($Bucket -NotIn $ScoopBuckets) {
            scoop bucket add "$Bucket"
        }
    }

    $RepoPath = "$PSScriptRoot/repo"
    If (-Not (Test-Path -Path "$RepoPath" -PathType Any)) {
        git clone --depth 1 "$URL" "$RepoPath"
    }

    SetupWinRM

    If ($WSL) {
        SetupWSL
    }
}

# Launch WinRM and create inbound network rule.
Function SetupWinRM {
    $TempFile = [System.IO.Path]::GetTempFileName() -Replace ".tmp", ".ps1"
    Write-Output "Setting up WinRM..."
    DownloadFile "https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1" $TempFile
    & $TempFile
}

# Install WSL2 with Ubuntu.
#
# Implemented based on instructions at
# https://docs.microsoft.com/en-us/windows/wsl/install-win10.
Function SetupWSL {
    If (-Not (Get-Command wsl -ErrorAction SilentlyContinue)) {
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

        Write-Output "Restart your system to finish WSL installation."
        Write-Output "Then run bootware setup again to install Ubuntu."
        Exit 0
    }

    If (-Not (Get-Command ubuntu -ErrorAction SilentlyContinue)) {
        $TempFile = [System.IO.Path]::GetTempFileName() -Replace ".tmp", ".msi"
        Write-Output "Downloading WSL update. Follow the GUI for installation."
        DownloadFile "https://wslstorestorage.blob.core.windows.net/wslblob/wsl_update_x64.msi" $TempFile
        Start-Process -Wait $TempFile

        wsl --set-default-version 2

        $TempFile = [System.IO.Path]::GetTempFileName() -Replace ".tmp", ".zip"
        $TempDir = $TempFile -Replace ".zip", ""
        Write-Output "Downloading Ubuntu image. Follow the prompt for installation."
        DownloadFile "https://aka.ms/wslubuntu2004" $TempFile
        
        Expand-Archive "$TempFile" "$TempDir"
        & "$TempDir/ubuntu2004.exe"
    }

    If (-Not (wsl command -v bootware)) {
        Write-Output "Installing a WSL copy of Bootware."
        wsl curl -LSfs https://raw.githubusercontent.com/wolfgangwazzlestrauss/bootware/master/install.sh `| bash

    }
}

# Subcommand to update Bootware script
Function Update() {
    $ArgIdx = 0
    $Version = "master"

    ForEach ($Arg in $Args) {
        Switch ($Arg) {
            {$_ -In "-h", "--help"} {
                Usage "update"
                Exit 0
            }
            {$_ -In "-v", "--version"} {
                $Version = $Args[0][$ArgIdx + 1]
                $ArgIdx += 2
            }
        }
    }

    $SrcURL = "https://raw.githubusercontent.com/wolfgangwazzlestrauss/bootware/$Version/bootware.ps1"
    DownloadFile "$SrcURL" "$PSScriptRoot/bootware.ps1"

    # Update WSL copy of Bootware.
    If (Get-Command wsl -ErrorAction SilentlyContinue) {
        wsl bootware update --version `> /dev/null
    }

    # Update playbook repository.
    $RepoPath = "$PSScriptRoot/repo"
    If (Test-Path -Path "$RepoPath" -PathType Container) {
        git -C "$RepoPath" pull
    }

    Write-Output "Updated to version $(bootware --version)."
}

# Print Bootware version string.
Function Version() {
    Write-Output "Bootware 0.3.0"
}

# Script entrypoint.
Function Main() {
    $Slice = $Args[0][1..($Args[0].Length-1)]

    Switch ($Args[0][0]) {
        {$_ -In "-h", "--help"} {
            Usage "main"
            Exit 0
        }
        {$_ -In "-v", "--version"} {
            Version
            Exit 0
        }
        "bootstrap" {
            Bootstrap $Slice
            Exit 0
        }
        "config" {
            Config $Slice
            Exit 0
        }
        "setup" {
            Setup $Slice
            Exit 0
        }
        "update" {
            Update $Slice
            Exit 0
        }
    }

    Usage "main"
}

Main $Args
