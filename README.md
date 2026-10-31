# TBH: Task Bar Hero — 游戏 + TBH助手 Docker 化工程

把 [TBH: Task Bar Hero](https://store.steampowered.com/app/3678970)（Steam 免费游戏，appid **3678970**）和
[TBHHelper 直连版](https://github.com/buguniaoOVO/TBHHelper)（Frida 托管助手）打包进容器，在 Linux 服务器上无人值守挂机、多开。

```
┌────────────────────────── 容器实例 1（wine 版） ──────────────────────────┐
│  Xvfb :99 ── x11vnc :5900 ── websockify :6080 (noVNC 浏览器观察/首次登录)  │
│     │                                                                     │
│  Wine prefix (win64, /data/prefix 持久卷)                                  │
│   ├─ Steam 客户端（-silent -login 自动登录，ssfn/loginusers 持久化免验证）   │
│   ├─ C:\games\tbh  ← steamcmd 匿名预装 app 3678970（免费游戏）             │
│   └─ C:\opt\tbh    ← TBHHelper（PyInstaller + Tk + frida python）          │
│                                                                           │
│  frida 注入游戏进程 (GameAssembly.dll, IL2CPP) —— 与原生 Windows 一致      │
└───────────────────────────────────────────────────────────────────────────┘
  多开 = 多容器（独立 prefix / 独立 Steam 账号，天然隔离，替代 Sandboxie）
```

## 三条路线对比

| 路线 | 结论 | 位置 |
|---|---|---|
| Windows 容器 | ✗ 不可行：无交互桌面会话、无 D3D/GPU 直通，Unity IL2CPP 起不来，且只能跑在 Windows 宿主 | — |
| **Wine 容器（本工程主线）** | ⚠ 可行，已交付；Frida×Wine 注入与游戏任务栏依赖为实测项 | `wine/` |
| Linux 容器 + KVM Windows 金盘 | ✓ 最稳（与原生一致）；金盘需带 KVM 的宿主机做一次 | `kvm/` |

## 快速开始（Wine 版）

镜像由 GitHub Actions 构建并推送 GHCR：
`ghcr.io/aewatw421/tbh-wine:latest`（Actions 里把包可见性改为 public，或 `docker login ghcr.io` 拉取）。

```bash
# 1. 准备一个数据卷目录（Steam 数据 / wine prefix / 游戏全在这里）
mkdir -p /srv/tbh/inst1 && cd /srv/tbh/inst1

# 2. 起容器（首次进入需要通过 noVNC 完成 Steam 登录与 Steam Guard）
docker run -d --name tbh-1 \
  -p 6080:6080 -p 5900:5900 \
  -v /srv/tbh/inst1:/data \
  -e SCREEN=1600x900x24 \
  -e PREINSTALL=1 \
  --shm-size=1g --memory=5g \
  --restart unless-stopped \
  ghcr.io/aewatw421/tbh-wine:latest

# 3. 浏览器打开 http://<host>:6080/vnc.html （或 VNC 客户端连 5900）
#    - 首次：若未设 STEAM_USER/PASS，在 Steam 登录窗口手动登录，通过 Steam Guard
#    - 登录一次后 ssfn/loginusers.vdf 已落盘 /data/prefix，之后容器重启自动免验证登录
#    - 确认游戏出现在库中（steamcmd 预装失败时手动在商店点“安装”，下载完即持久化）
#    - 打开 TBH助手，在“账号”页连接进程 → 配置规则 → 一键开启

# 4. 之后提供凭据即可全自动（可选）：
docker rm -f tbh-1
docker run -d --name tbh-1 \
  -v /srv/tbh/inst1:/data \
  -e STEAM_USER=你的账号 -e STEAM_PASS=你的密码 \
  -e AUTO_START_HELPER=1 \
  -p 6080:6080 -p 5900:5900 --shm-size=1g --memory=5g \
  --restart unless-stopped \
  ghcr.io/aewatw421/tbh-wine:latest
```

### 多开

同账号多处登录会互踢，多开 = **每实例一个 Steam 账号 + 一个数据卷**：

```bash
for i in 1 2 3; do
  docker run -d --name tbh-$i \
    -v /srv/tbh/inst$i:/data \
    -e STEAM_USER=acct$i -e STEAM_PASS=pass$i \
    -p 60$((8+i)):6080 -p 591$i:5900 \
    --shm-size=1g --memory=5g --restart unless-stopped \
    ghcr.io/aewatw421/tbh-wine:latest
done
```

或直接 `docker compose up -d --scale tbh=3`（见 `compose.yaml`）。

## 环境变量

| 变量 | 默认 | 说明 |
|---|---|---|
| `SCREEN` | `1600x900x24` | Xvfb 虚拟屏（宽x高x色深） |
| `PREINSTALL` | `1` | 启动时用 steamcmd 匿名预装游戏到 `C:\games\tbh` 并注册进 Steam 客户端 |
| `STEAM_USER` / `STEAM_PASS` | 空 | 自动登录 Steam；留空则 noVNC 手动登录一次（之后持久化免登录） |
| `STEAM_ARGS` | `-silent -noreactlogin` | Steam 客户端附加参数 |
| `AUTO_START_HELPER` | `1` | Steam 就绪后自动拉起 TBH助手 |
| `HELPER_DELAY` | `25` | 启动助手前等待秒数（等游戏进主界面） |
| `USE_VIRTUAL_DESKTOP` | `1` | 用 `wine explorer /desktop=…` 虚拟桌面（带模拟任务栏，任务栏游戏更稳） |
| `ENABLE_DXVK` | `0` | 1=安装 DXVK（走 Vulkan/lavapipe）；0=wined3d+GL(llvmpipe)。黑屏时切换试 |
| `VNC_PASSWORD` | 空 | VNC 密码（建议设置；noVNC 走 websocket 同样校验） |

## 构建与 CI

- `.github/workflows/build-wine-image.yml`：push `wine/**` 或手动触发 → buildx 构建 → 推 GHCR（`GITHUB_TOKEN` 登录，GHA 缓存层）。
- `.github/workflows/build-kvm-image.yml`：构建 KVM 运行器镜像（构建不需要 KVM，运行才需要 `/dev/kvm`）。

本机自建：

```bash
docker build -f wine/Dockerfile -t tbh-wine:local .
docker run --rm -v $PWD/data:/data tbh-wine:local steamcmd-version
```

## KVM 金盘路线（Wine 实测失败时的退路）

见 [kvm/make-golden.md](kvm/make-golden.md)：在带 KVM 的 Linux 宿主机上做一次 Windows 金盘
（autologon + Steam + 游戏 + 助手 + 自启），之后每实例一条命令、COW overlay 秒开。

```bash
docker run -d --name tbh-vm1 \
  --device /dev/kvm -v /srv/tbh/golden:/data \
  -p 5910:5900 --memory=10g --restart unless-stopped \
  ghcr.io/aewatw421/tbh-kvm:latest
```

## 已知未知数与实测清单（Wine 路线）

上服务器前请先跑一遍这套验证（每个都可能是拦路虎，但都有退路）：

1. **Frida 注入 Wine 进程** —— 助手用 `frida.get_local_device().attach(pid)`（frida-core 走
   `CreateRemoteThread`+`LoadLibrary` 注入 agent DLL），Wine 实现了这些 API，社区有成功先例，
   但 IL2CPP 场景需实测。失败点 A：注入本身崩；失败点 B：`Process.enumerateModules()` 列不出
   `GameAssembly.dll`（Wine PEB 模块表）；失败点 C：助手对 `GameAssembly.dll` 的
   `size==114753536` 指纹校验在 Wine 下返回不同值 → 助手直接拒绝工作（脚本硬校验）。
2. **任务栏依赖** —— 游戏是“任务栏英雄”，若它 `FindWindow("Shell_TrayWnd")` 停靠，Wine 虚拟
   桌面（`/desktop=`）提供同名窗口类，大概率兼容；实测时优先 `USE_VIRTUAL_DESKTOP=1`。
3. **DX11 渲染** —— 默认 wined3d+GL(llvmpipe)；像素 2D 负载低，软渲染可行。异常换 `ENABLE_DXVK=1`。
4. **Steam 自动登录** —— 需先手动登录一次让 `ssfn*` 落盘；账号开了手机令牌的首次要输一次码。
5. **游戏自动更新** —— F2P 强更：Steam 客户端挂着会自动更；`PREINSTALL` 只负责首次落地。

## 风险声明（工程事实）

- 容器化不改变助手的自动化/内存修改性质：游戏服务器侧行为监控（issue #1 提到的检测面）依旧存在，
  机房 IP 段可能更敏感；封号风险由使用者自担。
- Steam 同一账号频繁多地登录/多实例会触发风控，多开务必一实例一号。
- TBHHelper 的释放包与其 GitHub 源码并不完全对应（Python 调度器闭源），本工程不改变这一事实。
