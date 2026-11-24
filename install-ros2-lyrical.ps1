<#
.SYNOPSIS
    Installs ROS 2 Lyrical Luth on Windows 11 from the official pre-built binaries.

.DESCRIPTION
    Automates the steps of the official guide:
    https://docs.ros.org/en/lyrical/Get-Started/Installation/Windows-Install-Binary.html

      1. Checks the system (Windows 11, x64).
      2. Creates the install root (default C:\dev).
      3. Installs pixi (conda-forge frontend) if it is not already installed.
      4. Downloads the newest ros2-lyrical-*-windows-release-amd64.zip from
         https://github.com/ros2/ros2/releases (or uses -ZipPath).
      5. Extracts it to <InstallRoot>\lyrical.
      6. Runs "pixi install" and "pixi run python preinstall_setup_windows.py".
      7. Writes ros2_env.bat / ros2_shell.bat helpers that source pixi + ROS 2.
      8. Runs the talker/listener demo to verify the install.

    Each step is skipped when it is already done, so the script is safe to re-run.

.PARAMETER InstallRoot
    Short path that holds the install. Keep it short (Windows path-length limit). Default C:\dev.

.PARAMETER ZipPath
    Use an already-downloaded ROS 2 Windows zip instead of downloading one.

.PARAMETER IncludePrerelease
    Allow beta / pre-release Lyrical builds when picking the newest zip.

.PARAMETER Force
    Re-extract ROS 2 even if <InstallRoot>\lyrical already exists (the old folder is renamed, not deleted).

.PARAMETER SkipTest
    Skip the talker/listener verification.

.PARAMETER Yes
    Do not ask for confirmation before installing pixi.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-ros2-lyrical.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\install-ros2-lyrical.ps1 -ZipPath "$env:USERPROFILE\Downloads\ros2-lyrical-20260807-windows-release-amd64.zip"
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\dev',
    [string]$ZipPath,
    [switch]$IncludePrerelease,
    [switch]$Force,
    [switch]$SkipTest,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'   # Invoke-WebRequest is very slow with the progress bar on PS 5.1
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Distro       = 'lyrical'
$RosDir       = Join-Path $InstallRoot $Distro
$DownloadDir  = Join-Path $InstallRoot 'downloads'
$ReleasesApi  = 'https://api.github.com/repos/ros2/ros2/releases?per_page=100'
$AssetPattern = '^ros2-lyrical-.*windows-release-amd64\.zip$'

function Write-Step([string]$msg) { Write-Host ""; Write-Host "==> $msg" -ForegroundColor Cyan }
function Write-Ok([string]$msg)   { Write-Host "    [ok] $msg" -ForegroundColor Green }
function Write-Warn2([string]$msg){ Write-Host "    [warn] $msg" -ForegroundColor Yellow }
function Fail([string]$msg)       { Write-Host ""; Write-Host "[error] $msg" -ForegroundColor Red; exit 1 }

function Invoke-Native([string]$exe, [string[]]$arguments) {
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { Fail "'$exe $($arguments -join ' ')' failed with exit code $LASTEXITCODE." }
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('Path', 'User')
    $pixiBin = Join-Path $env:USERPROFILE '.pixi\bin'
    $env:Path = (@($pixiBin, $user, $machine) | Where-Object { $_ }) -join ';'
}

# ---------------------------------------------------------------------------
Write-Step 'Checking system'
$os = Get-CimInstance Win32_OperatingSystem
$build = [int]$os.BuildNumber
if ($build -lt 22000) {
    Write-Warn2 "$($os.Caption) (build $build) detected. The Lyrical binaries officially support Windows 11 only; continuing anyway."
} else {
    Write-Ok "$($os.Caption) (build $build)"
}
if (-not [Environment]::Is64BitOperatingSystem) { Fail 'A 64-bit (x64) Windows is required.' }
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    Write-Warn2 'ARM64 CPU detected. The ROS 2 binaries are amd64 and will run under emulation, if at all.'
}
if ($InstallRoot.Length -gt 12) {
    Write-Warn2 "InstallRoot '$InstallRoot' is long. Windows path-length limits can break the install; a short path such as C:\dev is recommended."
}

# ---------------------------------------------------------------------------
Write-Step "Creating install location $InstallRoot"
New-Item -ItemType Directory -Force -Path $InstallRoot, $DownloadDir | Out-Null
Write-Ok $InstallRoot

# ---------------------------------------------------------------------------
Write-Step 'Checking for pixi'
Update-SessionPath
$pixi = Get-Command pixi -ErrorAction SilentlyContinue
if ($pixi) {
    Write-Ok "pixi found: $($pixi.Source) ($((& pixi --version) 2>$null))"
} else {
    Write-Host '    pixi is not installed. It will be installed for your user only (no admin rights) from https://pixi.sh/install.ps1'
    Write-Host '    and %USERPROFILE%\.pixi\bin will be added to your user PATH.'
    if (-not $Yes) {
        $answer = Read-Host '    Install pixi now? [Y/n]'
        if ($answer -and $answer -notmatch '^(y|yes)$') { Fail 'pixi is required. Install it from https://pixi.sh and re-run this script.' }
    }
    Invoke-RestMethod -UseBasicParsing 'https://pixi.sh/install.ps1' | Invoke-Expression
    Update-SessionPath
    $pixi = Get-Command pixi -ErrorAction SilentlyContinue
    if (-not $pixi) { Fail 'pixi was installed but is not on PATH. Open a new terminal and re-run this script.' }
    Write-Ok "pixi installed: $($pixi.Source)"
}

# ---------------------------------------------------------------------------
Write-Step "Installing ROS 2 $Distro binaries to $RosDir"
$alreadyInstalled = Test-Path (Join-Path $RosDir 'local_setup.bat')
if ($alreadyInstalled -and -not $Force) {
    Write-Ok "Already extracted at $RosDir (use -Force to reinstall)."
} else {
    if (-not $ZipPath) {
        Write-Host '    Looking up the newest Lyrical Windows release on GitHub...'
        try {
            $releases = Invoke-RestMethod -UseBasicParsing -Uri $ReleasesApi -Headers @{ 'User-Agent' = 'ros2-lyrical-installer' }
        } catch {
            Fail "Could not query $ReleasesApi ($($_.Exception.Message)). Download the zip manually from https://github.com/ros2/ros2/releases and pass it with -ZipPath."
        }
        $candidates = foreach ($r in $releases) {
            if ($r.draft) { continue }
            if ($r.prerelease -and -not $IncludePrerelease) { continue }
            foreach ($a in $r.assets) {
                if ($a.name -match $AssetPattern) {
                    [pscustomobject]@{ Tag = $r.tag_name; Published = [datetime]$r.published_at; Name = $a.name; Url = $a.browser_download_url; Size = $a.size }
                }
            }
        }
        $asset = $candidates | Sort-Object Published -Descending | Select-Object -First 1
        if (-not $asset) {
            Fail "No asset matching '$AssetPattern' found. Try -IncludePrerelease, or download the zip from https://github.com/ros2/ros2/releases and pass -ZipPath."
        }
        Write-Ok "Release $($asset.Tag): $($asset.Name) ($([math]::Round($asset.Size / 1MB)) MB)"
        $ZipPath = Join-Path $DownloadDir $asset.Name
        if ((Test-Path $ZipPath) -and ((Get-Item $ZipPath).Length -eq $asset.Size)) {
            Write-Ok "Using previously downloaded $ZipPath"
        } else {
            Write-Host "    Downloading to $ZipPath (this can take a while)..."
            $tmpZip = "$ZipPath.partial"
            Invoke-WebRequest -UseBasicParsing -Uri $asset.Url -OutFile $tmpZip
            if ((Get-Item $tmpZip).Length -ne $asset.Size) { Fail 'Download size mismatch; please re-run the script.' }
            Move-Item -Force $tmpZip $ZipPath
            Write-Ok 'Download complete.'
        }
    } elseif (-not (Test-Path $ZipPath)) {
        Fail "ZipPath '$ZipPath' does not exist."
    }

    $extractDir = Join-Path $InstallRoot "_extract_$Distro"
    if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
    New-Item -ItemType Directory -Path $extractDir | Out-Null
    Write-Host "    Extracting $([IO.Path]::GetFileName($ZipPath))..."
    $tar = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (Test-Path $tar) {
        & $tar -xf $ZipPath -C $extractDir
        if ($LASTEXITCODE -ne 0) { Fail 'Extraction with tar.exe failed.' }
    } else {
        Expand-Archive -Path $ZipPath -DestinationPath $extractDir -Force
    }

    # The zip's top-level folder name varies between releases; find the folder that holds local_setup.bat.
    $setup = Get-ChildItem -Path $extractDir -Filter 'local_setup.bat' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $setup) { Fail "local_setup.bat not found inside the zip (extracted to $extractDir). Is this a ROS 2 Windows release zip?" }

    if (Test-Path $RosDir) {
        $backup = "$RosDir.old_$(Get-Date -Format yyyyMMdd_HHmmss)"
        Write-Warn2 "Moving existing $RosDir to $backup"
        Move-Item $RosDir $backup
    }
    Move-Item $setup.Directory.FullName $RosDir
    Remove-Item -Recurse -Force $extractDir -ErrorAction SilentlyContinue
    Write-Ok "ROS 2 extracted to $RosDir"
}

# ---------------------------------------------------------------------------
Write-Step 'Installing pixi dependencies'
if (-not (Test-Path (Join-Path $RosDir 'pixi.toml'))) {
    # The release zip is expected to ship pixi.toml; fall back to the one in the ros2/ros2 repo branch.
    Write-Warn2 'pixi.toml not found in the ROS 2 folder; downloading it from github.com/ros2/ros2 (lyrical branch).'
    Invoke-WebRequest -UseBasicParsing -Uri 'https://raw.githubusercontent.com/ros2/ros2/lyrical/pixi.toml' -OutFile (Join-Path $RosDir 'pixi.toml')
}
Push-Location $RosDir
try {
    Invoke-Native 'pixi' @('install')
    Write-Ok 'pixi environment ready.'

    Write-Step 'Running preinstall setup script'
    if (Test-Path 'preinstall_setup_windows.py') {
        Invoke-Native 'pixi' @('run', 'python', 'preinstall_setup_windows.py')
        Write-Ok 'preinstall_setup_windows.py completed.'
    } else {
        Write-Warn2 'preinstall_setup_windows.py not present in this release; skipping.'
    }
} finally {
    Pop-Location
}

# ---------------------------------------------------------------------------
Write-Step 'Writing environment helpers'
# Equivalent to the guide's "pixi shell" + "call local_setup.bat", but usable from scripts:
# "pixi shell-hook" prints the activation commands instead of starting a nested shell.
$envBat = @"
@echo off
rem Sources the pixi environment and ROS 2 $Distro into the current Command Prompt.
rem Usage:  call "$RosDir\ros2_env.bat"
pushd "$RosDir"
pixi shell-hook -s cmd > "%TEMP%\ros2_${Distro}_pixi_hook.bat"
if errorlevel 1 (
  echo [ros2_env] pixi shell-hook failed. Is pixi on PATH?
  popd
  exit /b 1
)
call "%TEMP%\ros2_${Distro}_pixi_hook.bat"
popd
call "$RosDir\local_setup.bat"
"@
$shellBat = @"
@echo off
rem Opens a new Command Prompt with ROS 2 $Distro ready to use.
cmd /k "call "$RosDir\ros2_env.bat" && echo ROS 2 $Distro environment ready. Try: ros2 run demo_nodes_cpp talker"
"@
Set-Content -Path (Join-Path $RosDir 'ros2_env.bat')   -Value $envBat   -Encoding Ascii
Set-Content -Path (Join-Path $RosDir 'ros2_shell.bat') -Value $shellBat -Encoding Ascii
Write-Ok "$RosDir\ros2_env.bat   (call it in any Command Prompt)"
Write-Ok "$RosDir\ros2_shell.bat (double-click to open a ROS 2 terminal)"

# ---------------------------------------------------------------------------
Write-Step 'Checking optional Visual Studio Build Tools 2022 (needed only to compile your own C++ packages)'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vc = $null
if (Test-Path $vswhere) {
    $vc = & $vswhere -products * -version '[17.0,18.0)' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2>$null | Select-Object -First 1
}
if ($vc) {
    Write-Ok "MSVC found: $vc"
} else {
    Write-Warn2 'Visual Studio Build Tools 2022 with "Desktop development with C++" not found.'
    Write-Host  '           Running ROS 2 works without it. To build C++ packages, install it from'
    Write-Host  '           https://visualstudio.microsoft.com/vs/older-downloads/ and build from the'
    Write-Host  '           "x64 Native Tools Command Prompt for VS 2022" using -DCMAKE_BUILD_TYPE=Release or RelWithDebInfo.'
}

# ---------------------------------------------------------------------------
if ($SkipTest) {
    Write-Step 'Skipping talker/listener test (-SkipTest).'
} else {
    Write-Step 'Verifying with the talker/listener demo (about 15 seconds)'
    $logDir   = Join-Path $InstallRoot 'logs'
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    $talkLog  = Join-Path $logDir 'talker.log'
    $listLog  = Join-Path $logDir 'listener.log'
    $envCall  = "call `"$RosDir\ros2_env.bat`""
    $talker   = Start-Process cmd.exe -ArgumentList "/c $envCall && ros2 run demo_nodes_cpp talker > `"$talkLog`" 2>&1" -WindowStyle Hidden -PassThru
    $listener = Start-Process cmd.exe -ArgumentList "/c $envCall && ros2 run demo_nodes_py listener > `"$listLog`" 2>&1" -WindowStyle Hidden -PassThru

    $heard = $false
    for ($i = 0; $i -lt 45 -and -not $heard; $i++) {
        Start-Sleep -Seconds 1
        if ((Test-Path $listLog) -and (Select-String -Path $listLog -Pattern 'I heard' -Quiet)) { $heard = $true }
    }
    foreach ($p in @($talker, $listener)) {
        if (-not $p.HasExited) { & taskkill.exe /PID $p.Id /T /F *> $null }
    }

    if ($heard) {
        Write-Ok 'Talker published and listener received messages. ROS 2 Lyrical is working.'
    } else {
        Write-Warn2 "The listener did not report 'I heard' within 45 s. Check the logs:"
        Write-Host  "           $talkLog"
        Write-Host  "           $listLog"
        Write-Host  '           A warning about missing RTI Connext DDS is normal. Windows Firewall may also prompt'
        Write-Host  '           you to allow python.exe / talker.exe on first run; allow it on private networks and re-run this script (finished steps are skipped).'
        exit 2
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "ROS 2 $Distro is installed in $RosDir" -ForegroundColor Green
Write-Host 'To use it in a new Command Prompt:'
Write-Host "    call $RosDir\ros2_env.bat"
Write-Host 'or double-click:'
Write-Host "    $RosDir\ros2_shell.bat"
