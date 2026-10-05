# 守望先锋 × 微信：不用改快捷键，选择威能时避免弹出微信截图
玩守望先锋时，微信也经常挂在后台。选威能要用 Alt 配合左右键，另一只手还在按着移动键。如果这时 A 没有松开，就容易碰上微信默认的截图快捷键 **Alt+A**：截图框突然弹出来，游戏卡一下，操作也被打断。


这个脚本就是为这个小麻烦写的。玩之前双击开启，守望先锋在前台时临时拦住 Alt+A；切出去回消息、看浏览器时，微信截图照常用。打完再双击恢复，不用每次改微信快捷键，也不用为了玩游戏关掉微信。

## 怎么用

在仓库页面点 **Code → Download ZIP**，把压缩包完整解压。日常只用下面两个文件：

| 文件 | 什么时候用 |
| --- | --- |
| [01_关闭游戏内截图快捷键.bat](01_关闭游戏内截图快捷键.bat) | 微信打开后、进游戏前双击，开启临时屏蔽 |
| [02_恢复截图快捷键.bat](02_恢复截图快捷键.bat) | 玩完双击，停止脚本、恢复正常输入 |

看到“已开启”后，窗口自动关闭是正常的，脚本会在后台继续运行。游戏刚启动时等约 1 秒，再试一下。切到桌面或微信时不必先关脚本，Alt+A 会自动放行。

适用于 Windows 10 / 11，使用系统自带的 Windows PowerShell。无需安装额外软件，也不提供 EXE。没有开机启动，重启或注销后就会停止，下次玩时再开。

## 哪些时候会拦截

脚本只认 **前台窗口所属的 `Overwatch.exe`**。窗口、无边框、全屏都按同一个规则处理：正在操作守望先锋时拦截，切到其他程序就放行。游戏只是挂在后台时，不会占住你的截图快捷键。

目前只处理 Alt+A。单独按 A、单独按 Alt、Alt+Tab，以及带 Ctrl、Shift 或 Windows 键的其他组合，都不在屏蔽范围内。重复双击开启不会多开；恢复脚本也只会停止本工具。

## 先在练习场试一下

保持微信开启，运行第一个 BAT，然后按你平时的操作顺序试一次：**先按住 A 移动，再按 Alt，并配合左右键选择威能**。看看截图还会不会弹出，也确认移动和选择操作是否正常。松开按键、切到桌面后，再试一次微信截图。

这里有个需要说清楚的地方：脚本拦截的是 **Alt+A 这组按键本身**，没有单独修改微信的截图功能。先按住 A 再按 Alt 时，已经放行的 A 按下事件会保留，对应的松开也会放行；如果先按 Alt 再按 A，游戏可能收不到 A 的按下事件。这两种顺序都建议试一下。如果影响你的游戏操作，双击恢复即可。

按键规则和脚本检查已经通过，但还没有完成真实守望先锋与微信同时运行时的兼容性测试，所以这里不把“所有情况下都不影响操作”当成保证。

## 突然不生效了怎么办

通常先试一遍：**恢复 → 确认微信已打开 → 重新开启 → 回游戏等约 1 秒**。这样会重新安装本工具的按键拦截。

如果游戏是以管理员身份运行的，脚本也可能需要用相同权限运行。窗口闪退、游戏进程改名、恢复失败等情况，在 [使用与修复教程](使用与修复教程.txt) 里有具体步骤。

日志保存在开启 BAT 同目录的 `运行日志.txt`，只记录启动、停止、错误和拦截次数，不记录聊天内容或输入文字。反馈问题时，附上错误信息和按键顺序就很有帮助。

## 为什么用 BAT，没写注册表

注册表里的常见单键映射不能表达“只在守望先锋前台时屏蔽 Alt+A”。为了保留切出游戏就能截图的行为，这里用 BAT 启动一个临时的 PowerShell 后台脚本，通过 Windows 键盘钩子判断是否拦截。

它不修改注册表或微信配置，不读写游戏内存、不注入游戏进程，也不模拟按键。想移除时先运行恢复，再删掉文件夹即可。

---

## 想看源码或自己改

两个 BAT 已经内嵌了运行所需的 PowerShell 和 C# 代码。普通使用只需下载、解压、双击；下面这些文件是留给想看实现或修改规则的人：

```text
.
├── 01_关闭游戏内截图快捷键.bat
├── 02_恢复截图快捷键.bat
├── 使用与修复教程.txt
├── src/
│   ├── AltAGuard.cs          # 按键规则与 Windows 钩子
│   ├── start-payload.ps1    # 启动、单实例控制和日志
│   └── stop-payload.ps1     # 停止后台脚本
├── tools/
│   ├── Build.ps1            # 从源码生成两个 BAT
│   └── Test-Distribution.ps1
├── tests/
│   └── Test-KeyFilter.ps1   # 43 项按键规则检查
└── .github/workflows/check.yml
```

后台每 500 毫秒刷新游戏进程列表，在收到 A 键事件时检查当前前台进程。A 的按下、松开会配对处理，避免切换窗口或松开 Alt 后留下错误的按键状态。

在仓库根目录执行以下命令，可以重新生成脚本并检查：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-KeyFilter.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Distribution.ps1
```

修改功能时编辑 `src/`，再重新生成 BAT，一起提交。BAT 使用无 BOM 的 UTF-8 和 CRLF 换行；PowerShell 源文件保留 UTF-8 BOM，兼容 Windows PowerShell 5.1。`-ExecutionPolicy Bypass` 只影响这一次进程，不永久修改系统策略。

GitHub Actions 会在 Windows 上检查按键规则和分发文件，不会启动后台键盘拦截。已有的验证包括 43 项按键规则，以及开启、重复开启、停止、重复停止。它们能检查脚本逻辑，实际游戏中的表现仍要自己试一下。

实现参考：[LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)、[KBDLLHOOKSTRUCT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct)、[UnhookWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unhookwindowshookex)。
