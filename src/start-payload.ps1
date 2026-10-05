param([ValidateSet('Start','Worker')][string]$Action = 'Start', [string]$ScriptPath)
$ErrorActionPreference = 'Stop'
# Change this only if Task Manager shows a different game executable name. No .exe suffix.
$TargetProcessNames = @('Overwatch')
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$prefix = 'Local\OW_ALT_A_GUARD_v1_' + $sid
$directory = [IO.Path]::GetDirectoryName($ScriptPath)
$logPath = Join-Path $directory '运行日志.txt'

function Write-GuardLog([string]$Message) {
    try {
        $line = [DateTime]::Now.ToString('yyyy-MM-dd HH:mm:ss') + ' | ' + $Message + [Environment]::NewLine
        [IO.File]::AppendAllText($logPath, $line, [Text.Encoding]::UTF8)
    } catch { }
}
function Test-Running {
    try { $m = [Threading.Mutex]::OpenExisting($prefix + '_Lock'); $m.Dispose(); return $true }
    catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
}
function Test-Ready {
    try {
        $r = [Threading.EventWaitHandle]::OpenExisting($prefix + '_Ready')
        try { return $r.WaitOne(0) } finally { $r.Dispose() }
    } catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
}

if ($Action -eq 'Start') {
    try {
        if (Test-Running) {
            if (Test-Ready) {
                Write-Host '保护已经开启，无需重复启动。' -ForegroundColor Green
                Write-Host '如果效果异常：先运行“02_恢复截图快捷键.bat”，再重新运行本脚本。'
                exit 0
            }
            throw '另一个实例正在启动或退出。请稍候；若持续无响应，先运行恢复脚本。'
        }
        # Environment transfer avoids interpolating user-controlled paths into command text.
        $env:OW_GUARD_SELF = $ScriptPath
        $command = '$s=[IO.File]::ReadAllText($env:OW_GUARD_SELF,[Text.Encoding]::UTF8); & ([ScriptBlock]::Create(($s -split ''(?m)^# POWERSHELL_PAYLOAD\r?$'',2)[1])) -Action Worker -ScriptPath $env:OW_GUARD_SELF # OW_ALT_A_GUARD_WORKER'
        $exe = Join-Path $PSHOME 'powershell.exe'
        $child = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile','-NonInteractive','-STA','-ExecutionPolicy','Bypass','-Command',('"' + $command + '"'))
        $watch = [Diagnostics.Stopwatch]::StartNew()
        $ok = $false
        while ($watch.Elapsed.TotalSeconds -lt 25) {
            if (Test-Ready) { $ok = $true; break }
            if ($child.HasExited) { break }
            Start-Sleep -Milliseconds 100
        }
        if (-not $ok) {
            if (-not $child.HasExited) { $child.Kill(); $child.WaitForExit(3000) | Out-Null }
            throw ('后台脚本未能启动。请查看同目录“运行日志.txt”和修复教程。')
        }
        Write-Host '已开启：仅守望先锋在前台时屏蔽 Alt+A。' -ForegroundColor Green
        Write-Host '切出游戏自动放行；关闭本窗口不会停止保护。'
        Write-Host '结束游戏后，双击“02_恢复截图快捷键.bat”即可停止后台脚本。'
        Write-Host ('后台进程 PID：' + $child.Id)
        exit 0
    } catch {
        Write-Host ('启动失败：' + $_.Exception.Message) -ForegroundColor Red
        Write-GuardLog ('LAUNCH ERROR: ' + $_.Exception.ToString())
        exit 1
    }
}

$mutex = $null
$stop = $null
$ready = $null
$ownsMutex = $false
try {
    $created = $false
    $mutex = [Threading.Mutex]::new($true, ($prefix + '_Lock'), [ref]$created)
    if (-not $created) { exit 0 }
    $ownsMutex = $true
    $stop = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, ($prefix + '_Stop'))
    $ready = [Threading.EventWaitHandle]::new($false, [Threading.EventResetMode]::ManualReset, ($prefix + '_Ready'))
    if ((Test-Path -LiteralPath $logPath) -and (Get-Item -LiteralPath $logPath).Length -gt 131072) {
        Copy-Item -LiteralPath $logPath -Destination ($logPath + '.old') -Force
        [IO.File]::WriteAllText($logPath, '', [Text.Encoding]::UTF8)
    }
    Write-GuardLog ('START PID=' + $PID + '; targets=' + ($TargetProcessNames -join ',') + '; foreground only')
    $source = @'
__CSHARP__
'@
    Add-Type -TypeDefinition $source -Language CSharp
    Write-GuardLog 'COMPILED; installing keyboard hook. Ready is reported by the launcher only after installation succeeds.'
    $result = [OverwatchAltAGuard.Guard]::Run($stop, $ready, $TargetProcessNames)
    Write-GuardLog ('STOP ' + $result)
} catch {
    Write-GuardLog ('WORKER ERROR: ' + $_.Exception.ToString())
    exit 1
} finally {
    if ($ready) { $ready.Reset() | Out-Null; $ready.Dispose() }
    if ($stop) { $stop.Dispose() }
    if ($mutex) {
        if ($ownsMutex) { $mutex.ReleaseMutex() }
        $mutex.Dispose()
    }
}
