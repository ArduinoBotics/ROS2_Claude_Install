# ROS 2 Lyrical Luth installer for Windows

A script that installs **ROS 2 Lyrical Luth** on Windows 11 from the official pre-built binaries, following
[the official Windows binary install guide](https://docs.ros.org/en/lyrical/Get-Started/Installation/Windows-Install-Binary.html).

## Quick start

1. Clone or download this repository on the Windows PC.
2. Double-click **`install.bat`**, or run this from PowerShell:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install-ros2-lyrical.ps1
   ```

3. Afterwards, open a ROS 2 terminal by double-clicking `C:\dev\lyrical\ros2_shell.bat`, or run
   `call C:\dev\lyrical\ros2_env.bat` in any Command Prompt.

No administrator rights are needed.

## What it does

| Step | Guide section | Notes |
|------|---------------|-------|
| Check the OS | System requirements | Warns if the PC isn't running Windows 11 x64 |
| Create `C:\dev` | Create a location | Change it with `-InstallRoot` (keep it short) |
| Install [pixi](https://pixi.sh) | Install pixi | Only if missing; asks first; installs for your user only |
| Download the newest `ros2-lyrical-*-windows-release-amd64.zip` | Install ROS 2 | Picks the newest non-beta release from [ros2/ros2 releases](https://github.com/ros2/ros2/releases) |
| Extract it to `C:\dev\lyrical` | Install ROS 2 | Uses Windows' built-in `tar.exe` |
| `pixi install` | Install Pixi dependencies | |
| `pixi run python preinstall_setup_windows.py` | Run preinstall script | |
| Write `ros2_env.bat` / `ros2_shell.bat` | Setup environment | Same as `pixi shell` + `call local_setup.bat`, but can be scripted |
| Check for VS Build Tools 2022 | Optional | Reports only; needed only to compile your own C++ packages |
| Talker/listener demo | Try some examples | Passes when the listener logs `I heard` |

You can safely re-run the script, because it skips steps that are already done.

## Options

| Flag | Purpose |
|------|---------|
| `-InstallRoot D:\ros` | Install somewhere other than `C:\dev` |
| `-ZipPath <file.zip>` | Use a zip you already downloaded instead of downloading one |
| `-IncludePrerelease` | Allow beta builds when picking the newest zip |
| `-Force` | Reinstall ROS 2 (the old folder is renamed, not deleted) |
| `-SkipTest` | Skip the talker/listener check |
| `-Yes` | Don't ask before installing pixi |

`install.bat` passes flags through, for example `install.bat -SkipTest`.

## Building your own packages

The binaries are built in **Release** mode. With MSVC, your own C++ nodes must be built as Release or RelWithDebInfo to stay ABI-compatible.
Install *Visual Studio Build Tools 2022* with the **Desktop development with C++** workload. Then, from the
**x64 Native Tools Command Prompt for VS 2022**, run:

```bat
call C:\dev\lyrical\ros2_env.bat
colcon build --cmake-args -DCMAKE_BUILD_TYPE=Release
```

## Troubleshooting

- **A warning that RTI Connext DDS is missing** is normal.
- **Windows Defender / SmartScreen** may flag the conda-forge/pixi install. As the official guide notes, choose *More info → Run anyway*.
- **A Windows Firewall prompt** may appear on the first demo run. Allow access on private networks, then re-run.
- **The demo check fails:** read `C:\dev\logs\talker.log` and `C:\dev\logs\listener.log`.
- **A download is blocked or fails:** download the zip manually from the releases page and pass `-ZipPath`.

## Uninstall

Delete `C:\dev\lyrical` (for example `rmdir /s /q C:\dev\lyrical`). To remove pixi, delete `%USERPROFILE%\.pixi` and remove
`%USERPROFILE%\.pixi\bin` from your user PATH.
