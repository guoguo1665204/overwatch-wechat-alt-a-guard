$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$out = $root
[IO.Directory]::CreateDirectory($out) | Out-Null
$utf8 = [Text.UTF8Encoding]::new($false)
$source = [IO.File]::ReadAllText((Join-Path $root 'src\AltAGuard.cs'))
$start = [IO.File]::ReadAllText((Join-Path $root 'src\start-payload.ps1')).Replace('__CSHARP__', $source.TrimEnd())
$stop = [IO.File]::ReadAllText((Join-Path $root 'src\stop-payload.ps1'))
$header = @'
@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "OW_GUARD_SELF=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:OW_GUARD_SELF,[Text.Encoding]::UTF8); & ([ScriptBlock]::Create(($s -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1])) __ARGS__"
set "OW_GUARD_RESULT=%errorlevel%"
if "%OW_GUARD_NO_PAUSE%"=="1" exit /b %OW_GUARD_RESULT%
if not "%OW_GUARD_RESULT%"=="0" (
  echo.
  pause
) else (
  timeout /t 4 >nul
)
exit /b %OW_GUARD_RESULT%
# POWERSHELL_PAYLOAD
'@
function Write-Bat([string]$Name, [string]$Body, [string]$Arguments) {
    $content = ($header.Replace('__ARGS__', $Arguments).TrimEnd() + "`n" + $Body) -replace "\r?\n", "`r`n"
    [IO.File]::WriteAllText((Join-Path $out $Name), $content, $utf8)
}
Write-Bat '01_关闭游戏内截图快捷键.bat' $start '-Action Start -ScriptPath $env:OW_GUARD_SELF'
Write-Bat '02_恢复截图快捷键.bat' $stop ''
Write-Output $out
