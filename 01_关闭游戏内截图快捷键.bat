@echo off
setlocal DisableDelayedExpansion
chcp 65001 >nul
set "OW_GUARD_SELF=%~f0"
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:OW_GUARD_SELF,[Text.Encoding]::UTF8); & ([ScriptBlock]::Create(($s -split '(?m)^# POWERSHELL_PAYLOAD\r?$',2)[1])) -Action Start -ScriptPath $env:OW_GUARD_SELF"
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
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

namespace OverwatchAltAGuard
{
    // Keeps key-up delivery paired with any key-down already delivered.
    // No input is recorded or synthesized.
    public sealed class KeyFilter
    {
        private readonly bool[] modifiers = new bool[256];
        private bool aForwarded;
        private bool aBlocked;
        public int BlockedPresses { get; private set; }

        public void SetModifier(int key, bool down) { modifiers[key] = down; }
        public void SeedA(bool down) { aForwarded = down; }

        public bool Filter(int key, bool up, bool alt, bool protect)
        {
            if (key == 0x10) key = 0xA0;
            if (key == 0x11) key = 0xA2;
            if (key == 0xA0 || key == 0xA1 || key == 0xA2 || key == 0xA3 ||
                key == 0x5B || key == 0x5C)
            {
                modifiers[key] = !up;
                return false;
            }
            if (key != 0x41) return false;
            if (up)
            {
                bool block = aBlocked && !aForwarded;
                aForwarded = aBlocked = false;
                return block;
            }
            bool extra = modifiers[0xA0] || modifiers[0xA1] || modifiers[0xA2] ||
                modifiers[0xA3] || modifiers[0x5B] || modifiers[0x5C];
            if (protect && alt && !extra)
            {
                if (!aBlocked) BlockedPresses++;
                aBlocked = true;
                return true;
            }
            aForwarded = true;
            return false;
        }
    }

    public static class Guard
    {
        private delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
        [StructLayout(LayoutKind.Sequential)]
        private struct Message
        {
            public IntPtr hwnd;
            public uint message;
            public UIntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int x, y;
            public uint lPrivate;
        }
        [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint thread);
        [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hook);
        [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
        [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
        [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
        [DllImport("user32.dll", SetLastError = true)] private static extern int GetMessage(out Message message, IntPtr window, uint min, uint max);
        [DllImport("user32.dll")] private static extern bool PeekMessage(out Message message, IntPtr window, uint min, uint max, uint remove);
        [DllImport("user32.dll")] private static extern bool TranslateMessage(ref Message message);
        [DllImport("user32.dll")] private static extern IntPtr DispatchMessage(ref Message message);
        [DllImport("user32.dll", SetLastError = true)] private static extern UIntPtr SetTimer(IntPtr window, UIntPtr id, uint interval, IntPtr callback);
        [DllImport("user32.dll")] private static extern bool KillTimer(IntPtr window, UIntPtr id);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern IntPtr GetModuleHandle(string name);

        private static volatile int[] targetIds = new int[0];
        private static HookProc callback;
        private static IntPtr hook;
        private static KeyFilter filter;
        private static int scanBusy;
        private static int scanFailures;
        private static int callbackFailures;
        private static volatile bool stopping;
        private static readonly int[] modifierKeys = { 0xA0, 0xA1, 0xA2, 0xA3, 0x5B, 0x5C };

        private static void Scan(object state)
        {
            if (Interlocked.Exchange(ref scanBusy, 1) != 0) return;
            try
            {
                List<int> ids = new List<int>();
                foreach (string name in (string[])state)
                {
                    Process[] processes = Process.GetProcessesByName(name);
                    foreach (Process process in processes)
                    {
                        try { ids.Add(process.Id); }
                        catch (InvalidOperationException) { }
                        finally { process.Dispose(); }
                    }
                }
                targetIds = ids.ToArray();
            }
            catch
            {
                targetIds = new int[0]; // Failure leaves input untouched.
                Interlocked.Increment(ref scanFailures);
            }
            finally { Interlocked.Exchange(ref scanBusy, 0); }
        }

        private static bool IsGameForeground()
        {
            uint id;
            IntPtr window = GetForegroundWindow();
            if (window == IntPtr.Zero) return false;
            GetWindowThreadProcessId(window, out id);
            int[] ids = targetIds;
            for (int i = 0; i < ids.Length; i++) if (ids[i] == id) return true;
            return false;
        }

        private static void SyncModifiers()
        {
            foreach (int key in modifierKeys)
                filter.SetModifier(key, (GetAsyncKeyState(key) & 0x8000) != 0);
        }

        private static IntPtr OnKey(int code, IntPtr message, IntPtr data)
        {
            if (code >= 0 && !stopping)
            {
                int msg = message.ToInt32();
                if (msg == 0x100 || msg == 0x101 || msg == 0x104 || msg == 0x105)
                {
                    try
                    {
                        int key = Marshal.ReadInt32(data);
                        int flags = Marshal.ReadInt32(data, 8);
                        bool up = msg == 0x101 || msg == 0x105;
                        bool protect = key == 0x41 && IsGameForeground();
                        if (filter.Filter(key, up, (flags & 0x20) != 0, protect)) return new IntPtr(1);
                    }
                    catch { Interlocked.Increment(ref callbackFailures); }
                }
            }
            return CallNextHookEx(hook, code, message, data);
        }

        public static string Run(EventWaitHandle stop, EventWaitHandle ready, string[] names)
        {
            stopping = false;
            scanFailures = callbackFailures = 0;
            filter = new KeyFilter();
            Message message;
            PeekMessage(out message, IntPtr.Zero, 0, 0, 0);
            Scan(names);
            SyncModifiers();
            filter.SeedA((GetAsyncKeyState(0x41) & 0x8000) != 0);
            callback = OnKey;
            UIntPtr timerId = UIntPtr.Zero;
            System.Threading.Timer detector = null;
            try
            {
                if (stop.WaitOne(0)) return "Cancelled before start.";
                hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
                if (hook == IntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Keyboard hook could not be installed");
                timerId = SetTimer(IntPtr.Zero, UIntPtr.Zero, 100, IntPtr.Zero);
                if (timerId == UIntPtr.Zero) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error(), "Stop timer could not be installed");
                detector = new System.Threading.Timer(Scan, names, 500, 500);
                ready.Set();
                while (!stop.WaitOne(0))
                {
                    int result = GetMessage(out message, IntPtr.Zero, 0, 0);
                    if (result == 0) break;
                    if (result == -1) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
                    if (message.message == 0x113) SyncModifiers();
                    else { TranslateMessage(ref message); DispatchMessage(ref message); }
                }
                return "Blocked presses=" + filter.BlockedPresses + "; scan errors=" + scanFailures + "; callback errors=" + callbackFailures;
            }
            finally
            {
                stopping = true;
                ready.Reset();
                if (hook != IntPtr.Zero) { UnhookWindowsHookEx(hook); hook = IntPtr.Zero; }
                if (timerId != UIntPtr.Zero) KillTimer(IntPtr.Zero, timerId);
                if (detector != null) detector.Dispose();
                GC.KeepAlive(callback);
            }
        }
    }
}
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
