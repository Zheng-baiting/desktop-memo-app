param(
    [string]$MemoExe = (Join-Path $PSScriptRoot '../build/windows/x64/runner/Release/desktop_memo.exe'),
    [string]$ShortcutPath = (Join-Path ([Environment]::GetFolderPath('Desktop')) '桌面便利贴.lnk')
)
$ErrorActionPreference = 'Stop'
$MemoExe = (Resolve-Path -LiteralPath $MemoExe).Path
# Validate the native launcher before changing the task or shortcut.
$launcherExe = Join-Path (Split-Path -Parent $MemoExe) 'memo_launcher.exe'
$null = Resolve-Path -LiteralPath $launcherExe
$taskName = 'DesktopMemo-IndependentLaunch'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($existing -and (@($existing.Actions).Count -ne 1 -or $existing.Actions[0].Execute -ne $MemoExe)) {
    throw 'A different task already uses the independent launcher name.'
}
$action = New-ScheduledTaskAction -Execute $MemoExe -WorkingDirectory (Split-Path -Parent $MemoExe)
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
# No trigger: invoked by the desktop shortcut or the dated calendar task.
Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Description 'Run Desktop Memo independently of the requesting application, without a time limit.' -Force | Out-Null
& (Join-Path $PSScriptRoot 'update-independent-shortcut.ps1') -MemoExe $MemoExe -ShortcutPath $ShortcutPath
Write-Output 'Independent launch task and desktop shortcut installed.'
