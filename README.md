# 守望先锋 Alt+A 防截图冲突脚本

只在 **守望先锋处于前台** 时临时屏蔽 `Alt+A`，避免游戏过程中触发微信截图。切到桌面或其他程序时放行，使用第二个 BAT 可以彻底停止保护。

适用于 Windows 10 / 11。无需安装新软件，不分发 EXE，不修改注册表或微信配置。由系统自带的 Windows PowerShell 在后台运行。

> **使用限制：**拦截的是 `Alt+A` 组合本身，游戏也可能收不到其中的 A 按下事件。如果你需要在游戏中同时使用 Alt 和 A，请先在练习场测试。尚未完成真实守望先锋与微信同时运行时的兼容性验证。

## 快速使用

1. 在仓库页面点击 **Code → Download ZIP**，完整解压到可写文件夹。
2. 打开微信，双击根目录的 **`01_关闭游戏内截图快捷键.bat`**。
3. 看到“已开启”后进入游戏，等待约 1 秒让脚本识别游戏进程。
4. 游戏结束后双击 **`02_恢复截图快捷键.bat`**，看到“已恢复”即可。

| 文件 | 作用 |
| --- | --- |
| [01_关闭游戏内截图快捷键.bat](01_关闭游戏内截图快捷键.bat) | 开启前台游戏保护；这里“关闭”指屏蔽截图组合键 |
| [02_恢复截图快捷键.bat](02_恢复截图快捷键.bat) | 停止后台脚本并卸载本工具的拦截 |
| [使用与修复教程.txt](使用与修复教程.txt) | 自检、失效排查、权限问题、强制恢复和移除方法 |

两个 BAT 都是独立脚本，正常使用无需下载额外的源码依赖。命令窗口会自动关闭，保护脚本会继续在后台运行；它不会设置开机启动。重启或注销后保护自动结束。

## 生效范围

- 默认只识别 `Overwatch.exe`，且只在该进程的窗口处于前台时拦截。
- 支持按前台进程识别窗口、无边框和全屏游戏，不会屏蔽其他全屏应用。
- 单独的 A、单独的 Alt、Alt+Tab、Alt+F4 不在屏蔽规则中。
- Ctrl / Shift / Windows 键参与的其他组合不在屏蔽规则中。
- 重复开启不会叠加实例。需要重新安装拦截时，请先恢复再开启。
- 恢复脚本只停止本工具，不退出游戏、微信或其他 PowerShell 任务。

## 失效时先这样做

先运行恢复 BAT，再在微信已打开的情况下运行开启 BAT，回到游戏等待约 1 秒。

如果游戏使用管理员权限，可用相同权限运行两个 BAT。游戏进程改名、脚本无法启动或恢复失败时，按[完整修复教程](使用与修复教程.txt)处理。不要为修复本脚本删除注册表项，它没有写入持久键盘映射。

## 工作方式

BAT 内嵌 PowerShell 与 C# 源码，通过 `Add-Type` 加载 Windows 键盘钩子。后台每 500 毫秒刷新游戏进程列表；收到 A 键事件时检查当前前台进程。

按下和松开事件会配对处理：如果 A 的按下已经放行，就继续放行对应的松开，避免切换窗口或改变修饰键后留下错误的按键状态。

脚本不读写游戏内存、不注入游戏进程、不模拟按键，也不记录输入文字。日志仅包含生命周期、错误信息和拦截次数，写在开启 BAT 所在文件夹中。

参考：[LowLevelKeyboardProc](https://learn.microsoft.com/en-us/windows/win32/winmsg/lowlevelkeyboardproc)、[KBDLLHOOKSTRUCT](https://learn.microsoft.com/en-us/windows/win32/api/winuser/ns-winuser-kbdllhookstruct)、[UnhookWindowsHookEx](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-unhookwindowshookex)。

## 目录

```text
.
├── 01_关闭游戏内截图快捷键.bat
├── 02_恢复截图快捷键.bat
├── 使用与修复教程.txt
├── src/
│   ├── AltAGuard.cs          # 拦截规则与 Windows 钩子
│   ├── start-payload.ps1    # 启动、单实例控制和日志
│   └── stop-payload.ps1     # 请求退出并确认恢复
├── tools/
│   ├── Build.ps1           # 从源码生成两个独立 BAT
│   └── Test-Distribution.ps1
├── tests/
│   └── Test-KeyFilter.ps1   # 43 项按键规则检查
└── .github/workflows/check.yml
```

## 开发与验证

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Build.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-KeyFilter.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Distribution.ps1
```

修改功能时编辑 `src/`，随后重新生成根目录的 BAT，并一并提交。BAT 使用无 BOM 的 UTF-8 和 CRLF 换行；PowerShell 源文件保留 UTF-8 BOM，兼容 Windows PowerShell 5.1。执行参数仅影响当前 PowerShell 进程，不永久改变系统执行策略。

GitHub Actions 配置为在 Windows 上运行逻辑检查与分发脚本检查，不会启动后台键盘保护。

交付前已通过 43 项按键逻辑检查，以及开启、重复开启、停止、重复停止检查。自动测试不能代替实际游戏兼容性测试，请按教程在练习场自检。

提交问题时，可描述 Windows 版本、游戏进程名称、运行权限、复现步骤和错误信息。不要上传账号信息或无关的完整系统日志。
