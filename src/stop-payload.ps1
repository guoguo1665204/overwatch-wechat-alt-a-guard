$ErrorActionPreference = 'Stop'
$sid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$prefix = 'Local\OW_ALT_A_GUARD_v1_' + $sid
function Test-Running {
    try { $m = [Threading.Mutex]::OpenExisting($prefix + '_Lock'); $m.Dispose(); return $true }
    catch [Threading.WaitHandleCannotBeOpenedException] { return $false }
}
try {
    # Signal this tool only. Never kill other PowerShell, WeChat, or game processes.
    $requested = $false
    $watch = [Diagnostics.Stopwatch]::StartNew()
    do {
        if (-not (Test-Running)) {
            Write-Host '已恢复：本工具的 Alt+A 屏蔽已关闭，后台脚本已停止。' -ForegroundColor Green
            Write-Host '如果之前没有开启过保护，本次无需修改任何设置。'
            exit 0
        }
        if (-not $requested) {
            try {
                $stop = [Threading.EventWaitHandle]::OpenExisting($prefix + '_Stop')
                try { $stop.Set() | Out-Null; $requested = $true } finally { $stop.Dispose() }
            } catch [Threading.WaitHandleCannotBeOpenedException] { }
        }
        Start-Sleep -Milliseconds 100
    } while ($watch.Elapsed.TotalSeconds -lt 15)
    throw '后台脚本没有及时退出。请按教程中的“强制恢复”步骤处理。'
} catch {
    Write-Host ('恢复未完成：' + $_.Exception.Message) -ForegroundColor Red
    Write-Host '如果开启脚本是以管理员身份运行的，请用同一账户、同样的权限运行恢复脚本。'
    exit 1
}
