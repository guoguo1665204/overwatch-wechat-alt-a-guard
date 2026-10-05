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
