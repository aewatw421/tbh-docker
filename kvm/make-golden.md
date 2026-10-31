# Windows 金盘制作手册（KVM 路线）

Wine 路线实测不通（Frida 注入 / 任务栏 / DX11 任一环节失败）时走这条：**与原生 Windows 完全一致**，
代价是要在带 KVM 的 Linux 宿主机上做一次金盘，并自备 Windows 授权。

## 前置

- 宿主机：x86_64 Linux，`/dev/kvm` 可写，≥ 8 vCPU / 16GB RAM / 100GB 磁盘（每实例额外 20-40GB）
- Windows 10/11 x64 ISO（官方或已有授权介质）
- 一个 Steam 账号（游戏免费，但客户端必须登录；多开=多账号）

## 步骤

### 1. 装系统（一次性，约 20 分钟）

```bash
qemu-img create -f qcow2 /srv/tbh/golden/golden.qcow2 80G
qemu-system-x86_64 -enable-kvm -cpu host -smp 6 -m 8192 \
  -drive file=/srv/tbh/golden/golden.qcow2,if=virtio,format=qcow2 \
  -cdrom /path/win11.iso \
  -netdev user,id=n0 -device virtio-net-pci,netdev=n0 \
  -vga std -device usb-tablet -usb -device usb-kbd -display vnc=:0
```

VNC 连 `5900` 走完 OOBE。**关键选项**：

- 分区后如果 virtio 磁盘识别不到，安装介质需挂 `virtio-win` 驱动盘（或改用 `-drive if=ide`）
- 建本地账号（非微软账号），**密码记住**——autologon 与 RDP 都要用
- 关掉休眠/睡眠、关掉 Windows Update 自动重启（`gpedit` 或注册表 `NoAutoRebootWithLoggedOnUsers=1`）
- 设静态分辨率 1600x900（或你要的尺寸），关闭 DPI 缩放 125%→100%

### 2. 自动登录（无桌面也要能跑 GUI）

```powershell
# 管理员 PowerShell
$u='tbh'; $p='YourPassword'
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v AutoAdminLogon /t REG_SZ /d 1 /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultUserName /t REG_SZ /d $u /f
reg add "HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" /v DefaultPassword /t REG_SZ /d $p /f
# 禁用锁屏
reg add "HKLM\SOFTWARE\Policies\Microsoft\Windows\Personalization" /v NoLockScreen /t REG_DWORD /d 1 /f
```

> 助手是 Tk GUI 程序，必须在**交互式会话**里运行。autologon 保证开机即有 session 1 桌面。

### 3. 装 Steam + 游戏 + 助手

1. 装 Steam 客户端，登录账号（过一次 Steam Guard，之后 `ssfn` 落盘免验证）
2. 商店页安装 **TBH: Task Bar Hero**（appid 3678970，免费），等下载完（约 2GB）
3. 把 [TBHHelper 直连版](https://github.com/buguniaoOVO/TBHHelper/releases) 解压到 `C:\TBHHelper`
4. 首次手动跑一遍：`TBH助手.exe` → 账号页“连接” → 确认能读到游戏进程与用户名 → 配好规则 → 一键开启
   （这一步验证 Frida 注入链路在金盘里是通的；通了以后这条路基本不会坏）

### 4. 开机自启（进入桌面即全自动）

```powershell
$action  = New-ScheduledTaskAction -Execute 'C:\TBHHelper\TBH助手.exe'
$trigger = New-ScheduledTaskTrigger -AtLogOn
$set     = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit 0
Register-ScheduledTask -TaskName 'TBHHelper' -Action $action -Trigger $trigger -Settings $set -RunLevel Highest
```

游戏本身也会自启（Steam 设置里“登录后启动游戏”，或同样加一个 AtLogOn 任务）。

### 5. 收尾成金盘

```powershell
# VM 内执行
shutdown /s /t 0
```

关机后：

```bash
qemu-img convert -O qcow2 -c /srv/tbh/golden/golden.qcow2 /srv/tbh/golden/golden.compact.qcow2
mv /srv/tbh/golden/golden.compact.qcow2 /srv/tbh/golden/golden.qcow2
# 金盘只读保存，防止误改
chmod 444 /srv/tbh/golden/golden.qcow2
```

### 6. 跑实例

```bash
docker run -d --name tbh-vm1 \
  --device /dev/kvm \
  -v /srv/tbh/golden:/data/golden:ro \
  -v /srv/tbh/inst1:/data/overlays \
  -e INSTANCE_NAME=inst1 -e VM_MEM_MB=6144 -e VM_CPUS=4 \
  -p 5910:5900 --memory=10g --restart unless-stopped \
  ghcr.io/aewatw421/tbh-kvm:latest
```

`INSTANCE_NAME` 决定子盘名（`/data/overlays/tbh-inst1.qcow2`）。`KEEP_OVERLAY=0` 时每次重启回到金盘状态（
适合“游戏卡死就重置”的场景）；`=1` 保留系统内改动（Steam 更新、账号状态）。

## 多开注意事项

- **一实例一 Steam 账号**：同账号多处登录会互踢，且触发风控
- 每个实例独立子盘 → 独立 `ssfn/loginusers.vdf` → 独立登录态
- CPU 超卖比建议 ≤ 1:1（游戏是常驻进程，像素渲染也吃单核），内存每实例 6-8GB
- 每个子盘会随使用增长（Steam 更新、日志），定期 `qemu-img info` 看实际占用并清理

## RDP 方式（比 VNC 体验好）

entrypoint 已把宿主 `3389` 转发到 VM：`-netdev user,hostfwd=tcp::3389-:3389`。
VM 内开启“远程桌面”后，直接 `mstsc /v:<host>:3389`。多实例需要把 `-p` 端口错开并在 entrypoint 里改
`hostfwd`（当前写死 3389 → 建议按 `INSTANCE_NAME` 生成不同端口）。
