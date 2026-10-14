param(
    [string]$MemoExe = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Release/desktop_memo.exe'),
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) '桌面便利贴.lnk')
)
$ErrorActionPreference = 'Stop'
$MemoExe = (Resolve-Path -LiteralPath $MemoExe).Path
$memoDirectory = Split-Path -Parent $MemoExe
$launcherExe = (Resolve-Path -LiteralPath (Join-Path $memoDirectory 'memo_launcher.exe')).Path
$iconPath = (Resolve-Path -LiteralPath (Join-Path $memoDirectory 'memo-cartoon.ico')).Path
$task = Get-ScheduledTask -TaskName 'DesktopMemo-IndependentLaunch' -ErrorAction Stop
if (@($task.Actions).Count -ne 1 -or $task.Actions[0].Execute -ne $MemoExe) {
    throw 'The existing independent-launch task points to a different application.'
}

# Only update the shortcut. Do not register or alter the existing task.
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($ShortcutPath)
$shortcut.TargetPath = $launcherExe
$shortcut.Arguments = ''
$shortcut.WorkingDirectory = $memoDirectory
$shortcut.IconLocation = "$iconPath,0"
$shortcut.Description = '由Windows独立启动桌面便利贴'
$shortcut.Save()
if (-not ('DesktopMemo.ShortcutRefresh' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace DesktopMemo {
    public static class ShortcutRefresh {
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        public static extern void SHChangeNotify(uint change, uint flags,
            string path, IntPtr unused);
    }
}
'@
}
# Refresh only this item (SHCNE_UPDATEITEM / SHCNF_PATHW | SHCNF_FLUSH).
[DesktopMemo.ShortcutRefresh]::SHChangeNotify(0x2000, 0x1005, [IO.Path]::GetFullPath($ShortcutPath), [IntPtr]::Zero)
Write-Output 'Independent launch shortcut updated.'
