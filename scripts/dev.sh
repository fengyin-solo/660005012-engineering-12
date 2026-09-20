#!/usr/bin/env bash
# 一键安装（首次运行时）并同时启动前后端开发服务。
# 用法: ./scripts/dev.sh [--skip-install]
#   --skip-install  跳过依赖检查（确认已执行过 ./scripts/install.sh 时可加快启动）
#
# 行为约定：
#   - 前端 http://127.0.0.1:3000 、后端 http://127.0.0.1:8000 同时启动后才算成功；
#   - 任一侧启动失败或运行中退出，打印该侧日志末尾并以非 0 状态码退出；
#   - Ctrl-C 会同时关闭两个服务。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/.venv"
LOG_DIR="$ROOT_DIR/logs"

SKIP_INSTALL=0
[[ "${1:-}" == "--skip-install" ]] && SKIP_INSTALL=1

if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_CYAN=$'\033[36m'; C_MAGENTA=$'\033[35m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_MAGENTA=""; C_RESET=""
fi
info() { printf '%s[dev]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
die()  { printf '%s[dev] 错误:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

[[ "$SKIP_INSTALL" == "1" ]] || "$ROOT_DIR/scripts/install.sh"

[[ -x "$VENV_DIR/bin/python" ]] || die "后端虚拟环境不存在，请先运行 ./scripts/install.sh"
[[ -d "$FRONTEND_DIR/node_modules" ]] || die "前端依赖未安装，请先运行 ./scripts/install.sh"

mkdir -p "$LOG_DIR"
: > "$LOG_DIR/backend.log"
: > "$LOG_DIR/frontend.log"

BACKEND_PID=""
FRONTEND_PID=""
BACKEND_TAIL_PID=""
FRONTEND_TAIL_PID=""

cleanup() {
  trap - EXIT INT TERM
  for pid in "$FRONTEND_PID" "$BACKEND_PID"; do
    [[ -n "$pid" ]] && kill -- "-$pid" 2>/dev/null || true
  done
  [[ -n "$BACKEND_TAIL_PID" ]] && kill "$BACKEND_TAIL_PID" 2>/dev/null || true
  [[ -n "$FRONTEND_TAIL_PID" ]] && kill "$FRONTEND_TAIL_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

info "启动后端 FastAPI (http://127.0.0.1:8000) ..."
( cd "$BACKEND_DIR" && setsid "$VENV_DIR/bin/python" -m uvicorn app.main:app \
  --host 127.0.0.1 --port 8000 ) \
  >> "$LOG_DIR/backend.log" 2>&1 &
BACKEND_PID=$!

info "启动前端 Vite (http://127.0.0.1:3000) ..."
# -- --host 127.0.0.1 显式固定主机，端口由 vite.config.ts 锁定为 3000
( cd "$FRONTEND_DIR" && setsid npx --no-install vite --host 127.0.0.1 ) \
  >> "$LOG_DIR/frontend.log" 2>&1 &
FRONTEND_PID=$!

# 带前缀转发两路日志
tail -n +1 -f "$LOG_DIR/backend.log" 2>/dev/null | sed -u "s/^/${C_CYAN}[backend]${C_RESET}  /" &
BACKEND_TAIL_PID=$!
tail -n +1 -f "$LOG_DIR/frontend.log" 2>/dev/null | sed -u "s/^/${C_MAGENTA}[frontend]${C_RESET} /" &
FRONTEND_TAIL_PID=$!

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") >/dev/null 2>&1 && { exec 3>&- 3<&-; return 0; }; return 1; }
alive() { kill -0 "$1" 2>/dev/null; }

# 启动失败诊断：打印日志末尾并退出
fail_side() {
  local side="$1" logfile="$2"
  printf '\n%s[dev] %s启动失败，日志末尾（完整日志见 %s）：%s\n' \
    "$C_RED" "$side" "$logfile" "$C_RESET" >&2
  tail -n 30 "$logfile" >&2 || true
  exit 1
}

# 最长等待约 60 秒，两侧端口都可连通才算启动成功
BACKEND_READY=0
FRONTEND_READY=0
for _ in $(seq 1 120); do
  alive "$BACKEND_PID"  || fail_side "后端" "$LOG_DIR/backend.log"
  alive "$FRONTEND_PID" || fail_side "前端" "$LOG_DIR/frontend.log"
  [[ "$BACKEND_READY" == 0 ]]  && port_open 8000 && BACKEND_READY=1  && info "后端已就绪"
  [[ "$FRONTEND_READY" == 0 ]] && port_open 3000 && FRONTEND_READY=1 && info "前端已就绪"
  [[ "$BACKEND_READY" == 1 && "$FRONTEND_READY" == 1 ]] && break
  sleep 0.5
done

alive "$BACKEND_PID"  || fail_side "后端" "$LOG_DIR/backend.log"
alive "$FRONTEND_PID" || fail_side "前端" "$LOG_DIR/frontend.log"
[[ "$BACKEND_READY" == 1 && "$FRONTEND_READY" == 1 ]] \
  || die "等待服务就绪超时（后端 ready=$BACKEND_READY, 前端 ready=$FRONTEND_READY），请查看 logs/ 下日志。"

cat <<EOF

${C_GREEN}开发环境已启动：${C_RESET}
  前端页面:  http://127.0.0.1:3000
  后端接口:  http://127.0.0.1:8000  (文档 /docs)
  日志目录:  $LOG_DIR
按 Ctrl-C 同时停止前后端。
EOF

# 任一侧退出即整体失败退出（CI/接手人能立即看到明确结果）
wait -n "$BACKEND_PID" "$FRONTEND_PID"
if ! alive "$BACKEND_PID"; then
  fail_side "后端" "$LOG_DIR/backend.log"
fi
if ! alive "$FRONTEND_PID"; then
  fail_side "前端" "$LOG_DIR/frontend.log"
fi
