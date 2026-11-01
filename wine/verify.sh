#!/usr/bin/env bash
# 容器内自检：确认 Wine×Frida 链路的每个环节状态（docker exec -it tbh-1 /usr/local/bin/verify.sh）
set -uo pipefail
LOG_DIR="${LOG_DIR:-/var/log/tbh}"

pass=0; fail=0
ok()  { echo "  ✅ $*"; pass=$((pass+1)); }
bad() { echo "  ❌ $*"; fail=$((fail+1)); }
inf() { echo "  ℹ️  $*"; }

echo "== 1. 显示/VNC =="
pgrep -f 'Xvfb :99' >/dev/null && ok "Xvfb :99 在跑（SCREEN=${SCREEN:-?}）" || bad "Xvfb 未运行"
pgrep x11vnc >/dev/null && ok "x11vnc :5900 在跑" || bad "x11vnc 未运行（无法观察桌面）"
pgrep websockify >/dev/null && ok "noVNC :6080 在跑" || bad "websockify 未运行"

echo "== 2. Wine 与 prefix =="
wine --version >/dev/null 2>&1 && ok "wine $(wine --version 2>/dev/null | head -1)" || bad "wine 不可用"
[ -f "${WINEPREFIX:-/data/prefix}/system.reg" ] && ok "prefix 已初始化" || bad "prefix 缺失"

echo "== 3. 游戏内容 =="
GAME_DIR=""
for d in "${GAMES_DIR:-/data/prefix/drive_c/games/tbh}" \
         "${WINEPREFIX:-/data/prefix}/drive_c/Program Files (x86)/Steam/steamapps/common"/*/; do
  if [ -f "$d/GameAssembly.dll" ]; then GAME_DIR="${d%/}"; break; fi
done
if [ -n "$GAME_DIR" ]; then
  SZ=$(stat -c %s "$GAME_DIR/GameAssembly.dll")
  ok "GameAssembly.dll 存在（$(basename "$GAME_DIR")），磁盘大小 $SZ"
  inf "助手 JS 校验的是**进程内 SizeOfImage**（期望 114753536），与磁盘大小不同；"
  inf "若助手日志出现『当前游戏版本未校验』，说明 Wine 下模块尺寸上报与 Windows 不一致 → 走 KVM 路线"
else
  bad "游戏未安装：F2P 内容也需账号 license（匿名 steamcmd 必报 No subscription）"
  inf "两条路：① .env 填 STEAM_USER_1/STEAM_PASS_1 让 steamcmd 拉包；② noVNC 登录 Steam 后自动 steam://install/${STEAM_APP_ID:-3678970}"
fi
GAME_PID=$(pgrep -f -i 'tbh.*\.exe|TaskBarHero|taskbar.*\.exe' | head -1)
[ -n "$GAME_PID" ] && ok "游戏进程 pid=$GAME_PID" || bad "游戏进程不在（Steam 未登录或启动失败，看 $LOG_DIR/game.log）"

echo "== 4. Steam =="
pgrep -f 'steam\.exe' >/dev/null && ok "Steam 客户端在跑" || bad "Steam 未运行（$LOG_DIR/steam.log）"
if [ -n "${WINEPREFIX:-}" ] && ls "$WINEPREFIX/drive_c/Program Files (x86)/Steam/config/"ssfn* >/dev/null 2>&1; then
  ok "已存在 ssfn 登录票据（下次自动登录免 Steam Guard）"
else
  inf "无 ssfn 票据：需要 noVNC 手动登录一次"
fi

echo "== 5. 助手 =="
pgrep -f 'TBH.*\.exe|助手' >/dev/null 2>&1 && ok "助手进程在跑" || bad "助手未运行（AUTO_START_HELPER=${AUTO_START_HELPER:-1}，看 $LOG_DIR/helper.log）"
[ -d /opt/tbh ] && inf "助手文件：$(ls /opt/tbh | head -5 | tr '\n' ' ')…"

echo "== 6. Frida 注入判据（关键未知数） =="
if [ -f $LOG_DIR/helper.log ] && grep -qE "已连接游戏进程|连接成功|账号页" $LOG_DIR/helper.log; then
  ok "助手报告已连接游戏进程 → Wine×Frida 注入链路可用 🎉"
elif [ -f $LOG_DIR/helper.log ] && grep -qiE "operation not supported|permission denied|ptrace|attach.*fail|注入失败" $LOG_DIR/helper.log; then
  bad "检测到 attach 失败特征 → 改走 KVM 金盘路线（kvm/make-golden.md）"
else
  inf "helper.log 无明确连接判据：在 noVNC 里看助手「账号」页是否列出进程与用户名"
fi
ls $LOG_DIR/*.log 2>/dev/null | sed 's/^/      /'

echo
echo "结果：$pass 项通过，$fail 项失败"
[ "$fail" = 0 ] || echo "排障顺序：$LOG_DIR/{steam,game,helper,x11vnc}.log → README『已知未知数』"
exit 0
