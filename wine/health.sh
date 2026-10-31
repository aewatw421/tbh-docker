#!/usr/bin/env bash
# docker healthcheck：显示栈两条核心进程必须存活，否则标记 unhealthy
set -uo pipefail
pgrep -f 'Xvfb :99' >/dev/null 2>&1 || exit 1
pgrep x11vnc       >/dev/null 2>&1 || exit 1
exit 0
