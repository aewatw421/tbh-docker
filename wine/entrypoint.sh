#!/usr/bin/env bash
# TBH 游戏容器入口
# 用法：entrypoint.sh [run|login|setup|shell]   （默认 run）
#   run   —— 完整流程：显示栈 → prefix → Steam → 游戏 → TBH助手
#   login —— 只起显示栈与 Steam，供人工登录/装游戏/改助手设置（不自动开游戏）
#   setup —— 预热：prefix + winetricks + Steam 安装 + 游戏预装后退出
#   shell —— 起显示栈后进入 bash（调试）
set -uo pipefail

MODE="${1:-run}"
LOG() { echo "[tbh][${MODE}] $(date '+%F %T') $*"; }
DIE() { echo "[tbh][${MODE}][FATAL] $*" >&2; exit 1; }

export WINEPREFIX="${WINEPREFIX:-/data/prefix}"
export WINEARCH="${WINEARCH:-win64}"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES-mscoree,mshtml=}"
export DISPLAY="${DISPLAY:-:99}"
STEAM_APP_ID="${STEAM_APP_ID:-3678970}"
GAMES_DIR="${GAMES_DIR:-$WINEPREFIX/drive_c/games/tbh}"
SCREEN="${SCREEN:-1600x900x24}"
VD_SIZE="${VD_SIZE:-${SCREEN%x*}}"
STEAM_DIR="$WINEPREFIX/drive_c/Program Files (x86)/Steam"
HELPER_DELAY="${HELPER_DELAY:-25}"
AUTO_START_HELPER="${AUTO_START_HELPER:-1}"
USE_VIRTUAL_DESKTOP="${USE_VIRTUAL_DESKTOP:-1}"
VNC_PASSWORD="${VNC_PASSWORD:-}"
GAME_WAIT_SEC="${GAME_WAIT_SEC:-2400}"     # 等 Steam 客户端下载游戏的最长秒数
LOG_DIR="${LOG_DIR:-/var/log/tbh}"
STEAM_LOG="$LOG_DIR/steam.log"
GAME_LOG="$LOG_DIR/game.log"
HELPER_LOG="$LOG_DIR/helper.log"

mkdir -p /data "$LOG_DIR" || DIE "挂载卷不可写"
touch /data/.rwtest || DIE "挂载卷不可写"

# ---------- 容器内重启的幂等清理 ----------
# docker restart 保留可写层：旧 X 锁文件与残留 wine 进程必须先清掉
reset_environment() {
  LOG "清理上一轮残留（X 锁 / wine / 显示栈）"
  rm -f /tmp/.X99-lock /tmp/.X99-unix/X99 /tmp/.X11-unix/X99 2>/dev/null || true
  wineserver -k 2>/dev/null || true
  pkill -f 'steam\.exe'          2>/dev/null || true
  pkill -f 'steamwebhelper'      2>/dev/null || true
  pkill -f 'winedevice|services\.exe|explorer\.exe|svchost\.exe|rpcss\.exe' 2>/dev/null || true
  pkill x11vnc                   2>/dev/null || true
  pkill websockify               2>/dev/null || true
  pkill openbox                  2>/dev/null || true
  pkill -f 'Xvfb :99'            2>/dev/null || true
  sleep 2
}

# ---------- 显示栈（幂等：已有实例则复用） ----------
start_display() {
  if pgrep -f 'Xvfb :99' >/dev/null 2>&1; then
    XVFB_PID="$(pgrep -f 'Xvfb :99' | head -1)"
    LOG "复用已运行的 Xvfb :99 (pid=$XVFB_PID)"
  else
    rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 2>/dev/null || true
    LOG "启动 Xvfb :99 ($SCREEN)"
    Xvfb :99 -screen 0 "$SCREEN" -nolisten tcp &
    XVFB_PID=$!
    sleep 1
  fi
  pgrep x11vnc >/dev/null 2>&1 || {
    if [ -n "$VNC_PASSWORD" ]; then
      x11vnc -display :99 -forever -shared -rfbport 5900 -passwd "$VNC_PASSWORD" \
             -xkb -noxrecord -noxfixes -noxdamage >"$LOG_DIR/x11vnc.log" 2>&1 &
    else
      x11vnc -display :99 -forever -shared -rfbport 5900 -nopw \
             -xkb -noxrecord -noxfixes -noxdamage >"$LOG_DIR/x11vnc.log" 2>&1 &
    fi
  }
  pgrep websockify >/dev/null 2>&1 || \
    websockify --web /usr/share/novnc 6080 localhost:5900 >"$LOG_DIR/novnc.log" 2>&1 &
  xset s off -dpms 2>/dev/null || true
  pgrep openbox >/dev/null 2>&1 || openbox >"$LOG_DIR/openbox.log" 2>&1 &
  sleep 1
}

cleanup() {
  LOG "收到停止信号，收尾中…"
  wineserver -k 2>/dev/null || true
  [ -n "${XVFB_PID:-}" ] && kill "$XVFB_PID" 2>/dev/null || true
}
trap cleanup TERM INT

# ---------- wine prefix / 字体 / DXVK ----------
init_prefix() {
  if [ ! -f "$WINEPREFIX/system.reg" ]; then
    LOG "初始化 wine prefix（首次，约 1-2 分钟）"
    wineboot -u >"$LOG_DIR/wineboot.log" 2>&1
    wineserver -w
  fi
  if [ ! -f /data/.winetricks.done ]; then
    LOG "安装 winetricks 组件：corefonts cjkfonts"
    winetricks -q corefonts cjkfonts >"$LOG_DIR/winetricks.log" 2>&1 || LOG "winetricks 失败（继续）"
    touch /data/.winetricks.done
  fi
  if [ "${ENABLE_DXVK:-0}" = "1" ] && [ ! -f /data/.dxvk.done ]; then
    /usr/local/bin/install-dxvk.sh >"$LOG_DIR/dxvk.log" 2>&1 && touch /data/.dxvk.done \
      || LOG "DXVK 安装失败，继续用 wined3d"
  fi
}

# ---------- Steam 客户端 ----------
install_steam() {
  if [ ! -f "$STEAM_DIR/steam.exe" ]; then
    LOG "安装 Steam 客户端（静默）"
    curl -fsSL https://steamcdn-a.akamaihd.net/client/installer/SteamSetup.exe -o /tmp/SteamSetup.exe \
      || DIE "下载 SteamSetup.exe 失败"
    wine /tmp/SteamSetup.exe /S >"$LOG_DIR/steamsetup.log" 2>&1
    wineserver -w
    rm -f /tmp/SteamSetup.exe
  fi
}

# ---------- 游戏预装（需要账号 license，匿名拉不了 F2P 内容） ----------
preinstall_game() {
  if [ -f "$GAMES_DIR/GameAssembly.dll" ]; then LOG "游戏已在 $GAMES_DIR"; return 0; fi
  if [ -z "${STEAM_USER:-}" ]; then
    LOG "未提供 STEAM_USER：跳过 steamcmd（F2P 内容也需账号 license），将由 Steam 客户端下载"
    return 0
  fi
  LOG "steamcmd 以账号登录预装 app $STEAM_APP_ID → C:\\games\\tbh"
  /usr/local/bin/preinstall-game.sh >"$LOG_DIR/preinstall.log" 2>&1 \
    || LOG "steamcmd 预装失败（Steam Guard/风控常见），交给 Steam 客户端处理（$LOG_DIR/preinstall.log）"
}

# ---------- 定位游戏目录（steamcmd 路径或 Steam 库默认路径） ----------
find_game_dir() {
  local d
  if [ -f "$GAMES_DIR/GameAssembly.dll" ]; then echo "$GAMES_DIR"; return 0; fi
  while IFS= read -r d; do
    [ -f "$d/GameAssembly.dll" ] && { echo "$d"; return 0; }
  done < <(find "$STEAM_DIR/steamapps/common" -maxdepth 1 -mindepth 1 -type d 2>/dev/null)
  return 1
}

# ---------- Steam 登录 ----------
start_steam() {
  LOG "启动 Steam 客户端"
  if [ -n "${STEAM_USER:-}" ]; then
    # shellcheck disable=SC2086
    wine "$STEAM_DIR/steam.exe" -silent -noreactlogin -login "$STEAM_USER" "$STEAM_PASS" ${STEAM_ARGS:-} \
      >"$STEAM_LOG" 2>&1 &
  else
    LOG "未提供 STEAM_USER：请在浏览器 http://<host>:6080/vnc.html 手动登录一次（之后免登录）"
    # shellcheck disable=SC2086
    wine "$STEAM_DIR/steam.exe" -silent ${STEAM_ARGS:-} >"$STEAM_LOG" 2>&1 &
  fi
  local ready=0
  for _ in $(seq 1 90); do
    if pgrep -f 'steam\.exe' >/dev/null 2>&1; then ready=1; break; fi
    sleep 2
  done
  [ "$ready" = 1 ] && LOG "Steam 进程已就绪" || LOG "Steam 未检测到（180s），继续后续步骤"
  sleep 15
}

# ---------- 确保游戏就绪（触发客户端下载并等待） ----------
ensure_game() {
  find_game_dir >/dev/null && { LOG "游戏已就绪：$(find_game_dir)"; return 0; }
  LOG "触发 Steam 客户端安装：steam://install/$STEAM_APP_ID（F2P，登录后自动领 license 下载）"
  wine "$STEAM_DIR/steam.exe" "steam://install/$STEAM_APP_ID" >/dev/null 2>&1 || true
  local deadline=$(( SECONDS + GAME_WAIT_SEC ))
  while ! find_game_dir >/dev/null; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      LOG "等待 ${GAME_WAIT_SEC}s 仍未下载完成：请在 noVNC 的 Steam 里确认（网络/风控/需手动点安装）"
      return 1
    fi
    # 已登录前 steam://install 可能静默失败；每 5 分钟重触发一次
    if [ $(( SECONDS % 300 )) -lt 15 ]; then
      wine "$STEAM_DIR/steam.exe" "steam://install/$STEAM_APP_ID" >/dev/null 2>&1 || true
    fi
    sleep 15
  done
  LOG "游戏下载完成：$(find_game_dir)"
}

# ---------- 游戏 ----------
start_game() {
  local game_dir game_exe
  game_dir="$(find_game_dir)" || { LOG "游戏未就绪，跳过启动"; return 1; }
  game_exe="$(find "$game_dir" -maxdepth 1 -iname '*.exe' ! -iname '*crash*' -printf '%s\t%p\n' | sort -rn | head -1 | cut -f2)"
  [ -n "$game_exe" ] || { LOG "游戏目录中未找到主 exe"; return 1; }
  LOG "启动游戏：$(basename "$game_exe")（$(basename "$game_dir")）"
  (
    cd "$game_dir" || exit 1
    if [ "$USE_VIRTUAL_DESKTOP" = "1" ]; then
      # shellcheck disable=SC2086
      wine explorer /desktop=shell,"$VD_SIZE" "$(basename "$game_exe")" >"$GAME_LOG" 2>&1
    else
      # shellcheck disable=SC2086
      wine "$(basename "$game_exe")" >"$GAME_LOG" 2>&1
    fi
  ) &
}

# ---------- TBHHelper ----------
start_helper() {
  local helper_exe
  helper_exe="$(find /opt/tbh -maxdepth 2 -iname '*.exe' -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -1 | cut -f2)"
  if [ -z "$helper_exe" ]; then LOG "镜像内未找到助手 EXE"; return 1; fi
  LOG "等待 ${HELPER_DELAY}s 后启动助手：$(basename "$helper_exe")"
  sleep "$HELPER_DELAY"
  wine "$helper_exe" >"$HELPER_LOG" 2>&1 &
  LOG "助手已启动（日志 $HELPER_LOG）。在 UI 中：账号页「连接」→ 核对规则 →「一键开启」"
}

keepalive() {
  LOG "运行中。观察/操作：noVNC http://<host>:6080/vnc.html ；日志在 $LOG_DIR/"
  while sleep 30; do
    if ! kill -0 "${XVFB_PID:-0}" 2>/dev/null; then
      LOG "Xvfb 意外退出，容器退出以便 restart 策略拉起"
      exit 1
    fi
  done
}

case "$MODE" in
  run)
    reset_environment
    start_display
    init_prefix
    install_steam
    preinstall_game
    start_steam
    ensure_game
    start_game
    [ "$AUTO_START_HELPER" = "1" ] && start_helper || LOG "AUTO_START_HELPER=0：请在 noVNC 中手动打开 TBH助手"
    keepalive
    ;;
  login)
    reset_environment
    start_display
    init_prefix
    install_steam
    start_steam
    LOG "login 模式：完成 Steam 登录 / 安装游戏 / 调整助手设置后，Ctrl+C 退出本容器"
    keepalive
    ;;
  setup)
    reset_environment
    start_display
    init_prefix
    install_steam
    preinstall_game
    start_steam
    ensure_game
    LOG "setup 完成：游戏 $(find_game_dir || echo 未就绪) ；Steam 客户端已安装，退出"
    cleanup
    exit 0
    ;;
  shell)
    reset_environment
    start_display
    init_prefix
    LOG "shell 模式：DISPLAY=:99 已就绪，exit 退出"
    exec bash -i
    ;;
  *)
    DIE "未知模式：$MODE（可选 run|login|setup|shell）"
    ;;
esac
