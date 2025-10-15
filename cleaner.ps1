<#
.SYNOPSIS
  Temp File Cleaner by Mrudun Samant (PowerShell)

.DESCRIPTION
  Calculates and then removes temporary files, caches, logs, dumps, etc.
  Reports total space cleaned (in GB) at the end.
  
.NOTES
  Requires running as Administrator.
#>

#region — Ensure PowerShell 7 is Installed and Running
function Ensure-Pwsh7 {
    $isPwsh7 = $PSVersionTable.PSVersion.Major -ge 7
    if (-not $isPwsh7) {
        Write-Host "PowerShell 7 is not installed or this session is not using it." -ForegroundColor Yellow

        # Try to find if pwsh.exe exists already (installed manually)
        $pwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
        if (-not $pwshPath) {
            Write-Host "Installing PowerShell 7..." -ForegroundColor Cyan

            # Check if winget is available
            if (Get-Command winget.exe -ErrorAction SilentlyContinue) {
                try {
                    winget install --id Microsoft.Powershell --source winget --accept-source-agreements --accept-package-agreements -e
                    Start-Sleep -Seconds 10
                } catch {
                    Write-Host "Winget installation failed. Trying fallback method..." -ForegroundColor Red
                }
            }

            # After install, try to locate pwsh.exe again
            $pwshPath = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue
        }

        if ($pwshPath) {
            Write-Host "PowerShell 7 found at: $pwshPath" -ForegroundColor Green
            Write-Host "Relaunching script in PowerShell 7..." -ForegroundColor Cyan
            Start-Process -FilePath $pwshPath -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
            Exit
        } else {
            Write-Error "PowerShell 7 could not be installed or found. Please install it manually."
            Exit 1
        }
    }
}
Ensure-Pwsh7
#endregion


#region — Ensure Running as Administrator
function Ensure-RunAsAdmin {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
             ).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Write-Host "Relaunching as Administrator..." -ForegroundColor Yellow
        Start-Process -FilePath pwsh.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }
}
Ensure-RunAsAdmin
#endregion

Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     Temp File Cleaner by Mrudun Samant" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

#region — Define Folders
# Folders whose CONTENTS we delete and then RECREATE
$recreateFolders = @(
    "$env:SystemRoot\Prefetch",
    "$env:SystemRoot\Temp",
    "$env:TEMP",
    "$env:USERPROFILE\AppData\Local\Temp",
    "$env:USERPROFILE\AppData\Local\Microsoft\Windows\INetCache",
    "$env:USERPROFILE\AppData\Local\Google\Chrome\User Data\Default\Cache",
    "$env:LocalAppData\BraveSoftware\Brave-Browser\User Data\Default\Cache",
    "$env:LocalAppData\Opera Software\Opera Stable\Cache",
    "$env:LocalAppData\Opera Software\Opera GX Stable\Cache",
    "$env:SystemRoot\SoftwareDistribution\Download",
    "C:\ProgramData\Microsoft\Windows\WER",
    "C:\ProgramData\Microsoft\Windows\DeliveryOptimization\Cache",
    "$env:SystemRoot\Logs\CBS",
    "$env:LocalAppData\Microsoft\Windows\Explorer"
)

# Special cases:
#  - Firefox needs per-profile handling
#  - Crash dumps & Windows.old we just delete entirely (no recreation)
#  - MEMORY.DMP we delete
$removeOnly = @(
    "C:\Windows.old",                  # old Windows install
    "$env:SystemRoot\Minidump"         # minidump folder
)
$dumpFile = "$env:SystemRoot\MEMORY.DMP"
#endregion

#region — Calculate Total Size
Write-Host "Calculating total size of temporary files..." -ForegroundColor Green
$totalBytes = 0

function Add-FolderSize([string]$path) {
    if (Test-Path $path) {
        try {
            $sum = (Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
            if ($sum) { $script:totalBytes += $sum }
        } catch {
            Write-Warning "Failed to measure size: $path"
        }
    }
}

# Sum all recreate folders
foreach ($f in $recreateFolders) { Add-FolderSize $f }

# Firefox profiles cache2
$ffProfiles = Get-ChildItem -Path "$env:USERPROFILE\AppData\Local\Mozilla\Firefox\Profiles" -Directory -ErrorAction SilentlyContinue
foreach ($p in $ffProfiles) {
    Add-FolderSize "$($p.FullName)\cache2"
}

# Remove-only items
foreach ($f in $removeOnly) { Add-FolderSize $f }
if (Test-Path $dumpFile) { Add-FolderSize $dumpFile }

# Convert to GB
$cleanedGB = [math]::Round($totalBytes / 1GB, 2)
#endregion

#region — Perform Cleanup
Write-Host "Starting cleanup..." -ForegroundColor Green

# Helper to clear and recreate
function Clear-And-Recreate([string]$path) {
    if (Test-Path $path) {
        try {
            # Remove all contents
            Remove-Item -Path "$path\*" -Recurse -Force -ErrorAction Stop
        } catch {
            Write-Warning "Could not clear contents of $path"
        }
    }
    try {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "Cleaned + Recreated: $path"
    } catch {
        Write-Warning "Could not recreate $path"
    }
}

# 1. Recreate-list
foreach ($f in $recreateFolders) {
    Clear-And-Recreate $f
}

# 2. Firefox cache2 per profile
foreach ($p in $ffProfiles) {
    $c2 = "$($p.FullName)\cache2"
    Clear-And-Recreate $c2
}

# 3. Remove-only items
foreach ($f in $removeOnly) {
    if (Test-Path $f) {
        try {
            Remove-Item -Path $f -Recurse -Force -ErrorAction Stop
            Write-Host "Removed: $f"
        } catch {
            Write-Warning "Could not remove $f"
        }
    }
}

# 4. MEMORY.DMP
if (Test-Path $dumpFile) {
    try {
        Remove-Item -Path $dumpFile -Force -ErrorAction Stop
        Write-Host "Deleted MEMORY.DMP"
    } catch {
        Write-Warning "Could not delete MEMORY.DMP"
    }
}

#endregion

#region — Final Report
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "All temporary files cleaned successfully!" -ForegroundColor Green
Write-Host "Total Space Cleaned: $cleanedGB GB" -ForegroundColor Magenta
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Press Enter to exit"
#endregion
