#!/usr/bin/env bash
# ============================================================================
# 数值优化算法逐帧可视化教学平台 —— 本地开发一键脚本
#
# 用法:
#   bash scripts/dev.sh setup   # 安装前后端依赖（已安装时快速跳过，可重复执行）
#   bash scripts/dev.sh dev     # 先确保依赖就绪，再同时启动前后端（默认命令）
#   bash scripts/dev.sh check   # 提交前检查：后端语法/导入/API冒烟 + 前端类型检查/构建
#   bash scripts/dev.sh stop    # 停掉占用 8000 / 3000 端口的开发进程
#
# 约定:
#   后端 Python 3.11 + FastAPI，运行于 http://localhost:8000
#   前端 Node 20 + Vite，运行于 http://localhost:3000 （/api 代理到后端）
# ============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_DIR="$ROOT_DIR/backend"

VENV_DIR="$BACKEND_DIR/.venv"
VENV_PY="$VENV_DIR/bin/python"
PIP_CACHE_DIR="$ROOT_DIR/.pip-cache"
STATE_DIR="$ROOT_DIR/.cache/dev"
FRONTEND_STAMP="$STATE_DIR/frontend.deps"
BACKEND_STAMP="$STATE_DIR/backend.deps"
LOG_DIR="$ROOT_DIR/logs"

REQUIRED_PY_MAJOR=3
REQUIRED_PY_MINOR=11
REQUIRED_NODE_MAJOR=20
BACKEND_PORT=8000
FRONTEND_PORT=3000
READY_TIMEOUT=60

# 颜色输出（非 TTY 时自动退化为纯文本）
if [ -t 1 ]; then
  C_GREEN='\033[0;32m'; C_BLUE='\033[0;34m'; C_YELLOW='\033[0;33m'
  C_RED='\033[0;31m'; C_BOLD='\033[1m'; C_RESET='\033[0m'
else
  C_GREEN=''; C_BLUE=''; C_YELLOW=''; C_RED=''; C_BOLD=''; C_RESET=''
fi
info()  { printf "${C_BLUE}==>${C_RESET} ${C_BOLD}%s${C_RESET}\n" "$*"; }
ok()    { printf "${C_GREEN}✔${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}!${C_RESET} %s\n" "$*"; }
die()   { printf "${C_RED}✘ %s${C_RESET}\n" "$*" >&2; exit 1; }

# ----------------------------------------------------------------------------
# 环境探测
# ----------------------------------------------------------------------------
find_python311() {
  local candidate
  for candidate in python3.11 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      local ver
      ver="$("$candidate" -c 'import sys;print("%d.%d"%sys.version_info[:2])' 2>/dev/null || echo 0.0)"
      if [ "$ver" = "$REQUIRED_PY_MAJOR.$REQUIRED_PY_MINOR" ]; then
        command -v "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

check_prerequisites() {
  command -v git  >/dev/null 2>&1 || die "未找到 git，请先安装 git。"

  if command -v node >/dev/null 2>&1; then
    NODE_VER="$(node -p 'process.versions.node.split(".")[0]')"
  else
    NODE_VER=0
  fi
  if [ "$NODE_VER" -lt "$REQUIRED_NODE_MAJOR" ]; then
    die "未找到 Node.js $REQUIRED_NODE_MAJOR.x（当前: ${NODE_VER}）。请安装 Node 20，例如: nvm use（仓库根目录已提供 .nvmrc）。"
  fi
  command -v npm >/dev/null 2>&1 || die "未找到 npm，请随 Node.js 20 一起安装。"

  if PYTHON_BIN="$(find_python311)"; then
    export PYTHON_BIN
  else
    die "未找到 Python 3.11（后端唯一支持的运行环境）。请安装 Python 3.11 后重试。"
  fi
  command -v curl >/dev/null 2>&1 || command -v wget >/dev/null 2>&1 \
    || die "未找到 curl 或 wget（用于在缺失 pip 时引导 pip）。"
}

# ----------------------------------------------------------------------------
# 依赖安装（幂等，可安全重复执行）
# ----------------------------------------------------------------------------
file_hash() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1"
  else sha256sum "$1"; fi | awk '{print $1}'
}

deps_hash() {
  { file_hash "$FRONTEND_DIR/package.json"
    file_hash "$FRONTEND_DIR/package-lock.json"; } \
    | { command -v shasum >/dev/null 2>&1 && shasum -a 256 || sha256sum; } \
    | awk '{print $1}'
}

# 判断已有 venv 是否可用：可执行且 Python 小版本正确
venv_usable() {
  [ -x "$VENV_PY" ] || return 1
  "$VENV_PY" -c 'import sys; raise SystemExit(0 if sys.version_info[:2]==('$REQUIRED_PY_MAJOR','$REQUIRED_PY_MINOR') else 1)' 2>/dev/null
}

bootstrap_pip() {
  # 部分发行版（如 Debian/Ubuntu）的 venv 默认不带 pip，需要联网引导一次
  "$VENV_PY" -m pip --version >/dev/null 2>&1 && return 0
  info "venv 中没有 pip，使用 get-pip.py 引导..."
  local get_pip="$STATE_DIR/get-pip.py"
  mkdir -p "$STATE_DIR"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$get_pip"
  else
    wget -q https://bootstrap.pypa.io/get-pip.py -O "$get_pip"
  fi
  "$VENV_PY" "$get_pip" || return 1
}

setup_backend() {
  mkdir -p "$PIP_CACHE_DIR" "$STATE_DIR"
  local want_hash
  want_hash="$(file_hash "$BACKEND_DIR/requirements.lock")"

  if [ -f "$BACKEND_STAMP" ] && [ "$(cat "$BACKEND_STAMP")" = "$want_hash" ] && venv_usable \
     && "$VENV_PY" -c 'import fastapi, uvicorn, numpy' >/dev/null 2>&1; then
    ok "后端依赖已安装且为最新（Python $("$VENV_PY" -c 'import sys;print(".".join(map(str,sys.version_info[:3])))')），跳过。"
    return 0
  fi

  if [ -d "$VENV_DIR" ] && ! venv_usable; then
    warn "检测到已有的 .venv 不可用（通常是在其他操作系统/其他 Python 版本下创建），将删除重建。"
    rm -rf "$VENV_DIR"
  fi

  if [ ! -d "$VENV_DIR" ]; then
    info "创建后端虚拟环境 ($PYTHON_BIN -m venv backend/.venv) ..."
    "$PYTHON_BIN" -m venv --without-pip "$VENV_DIR"
  fi
  bootstrap_pip || die "pip 引导失败，请检查网络后重试（脚本不会改动系统 Python）。"

  info "安装后端依赖（使用本地缓存 .pip-cache/）..."
  "$VENV_PY" -m pip install --upgrade --cache-dir "$PIP_CACHE_DIR" pip wheel setuptools
  if [ -f "$BACKEND_DIR/requirements.lock" ]; then
    "$VENV_PY" -m pip install --cache-dir "$PIP_CACHE_DIR" \
      -r "$BACKEND_DIR/requirements.lock"
  else
    "$VENV_PY" -m pip install --cache-dir "$PIP_CACHE_DIR" \
      -r "$BACKEND_DIR/requirements.txt"
  fi
  "$VENV_PY" -c 'import fastapi, uvicorn, numpy' \
    || die "后端依赖安装后自检失败（fastapi/uvicorn/numpy 无法导入）。"

  echo "$want_hash" > "$BACKEND_STAMP"
  ok "后端依赖安装完成。"
}

setup_frontend() {
  mkdir -p "$STATE_DIR"
  local want_hash
  want_hash="$(deps_hash)"

  if [ -f "$FRONTEND_STAMP" ] && [ -x "$FRONTEND_DIR/node_modules/.bin/vite" ] \
     && [ "$(cat "$FRONTEND_STAMP")" = "$want_hash" ]; then
    ok "前端依赖已安装且为最新（node_modules），跳过。"
    return 0
  fi

  # 其他平台下安装的 node_modules（缺少对应平台的 rollup/esbuild 原生二进制）不可用
  if [ -d "$FRONTEND_DIR/node_modules" ] && [ ! -x "$FRONTEND_DIR/node_modules/.bin/vite" ]; then
    warn "检测到已有的 node_modules 不完整或来自其他平台，将删除后重装。"
    rm -rf "$FRONTEND_DIR/node_modules"
  fi

  (
    cd "$FRONTEND_DIR"
    if [ -f package-lock.json ]; then
      # lock 与 package.json 不一致时 npm ci 会报错，此时回退到 npm install 并更新锁文件
      if npm ci --no-audit --no-fund; then
        :
      else
        warn "npm ci 失败（package.json 与 package-lock.json 可能不同步），改用 npm install 更新锁文件..."
        npm install --no-audit --no-fund
      fi
    else
      npm install --no-audit --no-fund
    fi
  ) || die "前端依赖安装失败，请检查网络或 npm registry 配置。"

  echo "$want_hash" > "$FRONTEND_STAMP"
  ok "前端依赖安装完成。"
}

install_git_hooks() {
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  local hooks_dir
  hooks_dir="$(git -C "$ROOT_DIR" config core.hooksPath 2>/dev/null || true)"
  [ -n "$hooks_dir" ] && return 0   # 用户已自定义 hooks 路径，不覆盖
  local target
  target="$(git -C "$ROOT_DIR" rev-parse --git-path hooks)/pre-commit"
  if [ -f "$target" ] && ! grep -q "managed-by: scripts/dev.sh" "$target" 2>/dev/null; then
    warn "已存在自定义 .git/hooks/pre-commit，未覆盖；请手动加上: bash scripts/dev.sh check"
    return 0
  fi
  mkdir -p "$(dirname "$target")"
  cp "$ROOT_DIR/scripts/pre-commit" "$target"
  chmod +x "$target"
  ok "已安装 git pre-commit 钩子（提交前自动运行 bash scripts/dev.sh check）。"
}

cmd_setup() {
  check_prerequisites
  setup_backend
  setup_frontend
  install_git_hooks
  echo
  ok "全部就绪。启动开发服务器: bash scripts/dev.sh dev（或 make dev）"
}

# ----------------------------------------------------------------------------
# 启动 / 停止
# ----------------------------------------------------------------------------
port_in_use() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN -n -P >/dev/null 2>&1
    return $?
  fi
  # 无 lsof 时用 /proc 扫描（Linux）；最后退回 bash 的 /dev/tcp 探测
  if [ -d /proc/net ] && command -v python3 >/dev/null 2>&1; then
    [ -n "$(pids_on_port "$1")" ]
    return $?
  fi
  # /dev/tcp 连接成功即说明端口已被监听
  (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null && { exec 3>&- 3<&-; return 0; }
  return 1
}

# 输出监听指定端口的 PID 列表（依次尝试 lsof / fuser(Linux) / /proc 扫描）
pids_on_port() {
  local port="$1"
  if command -v lsof >/dev/null 2>&1; then
    lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true
  elif command -v fuser >/dev/null 2>&1; then
    fuser -n tcp "$port" 2>/dev/null | tr -s ' ' | tr ' ' '\n' | sed '/^$/d' || true
  elif [ -d /proc/net ] && command -v python3 >/dev/null 2>&1; then
    python3 - "$port" <<'EOF'
import os, sys
port = int(sys.argv[1])
inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(path).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        f = line.split()
        if f[3] == '0A' and int(f[1].rsplit(':', 1)[1], 16) == port:
            inodes.add(f[9])
pids = set()
for pid in (p for p in os.listdir('/proc') if p.isdigit()):
    try:
        fds = os.listdir('/proc/%s/fd' % pid)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink('/proc/%s/fd/%s' % (pid, fd))
        except OSError:
            continue
        if target.startswith('socket:[') and target[8:-1] in inodes:
            pids.add(int(pid))
print(' '.join(map(str, sorted(pids))))
EOF
  fi
}

kill_port() {
  local port="$1" pids
  pids="$(pids_on_port "$port")"
  [ -z "$pids" ] && return 0
  kill $pids 2>/dev/null || true
  # 等待 5 秒优雅退出，仍存活则强制结束
  local i
  for i in $(seq 1 5); do
    sleep 1
    local leftover
    leftover="$(pids_on_port "$port" || true)"
    [ -z "$leftover" ] && return 0
  done
  pids="$(pids_on_port "$port")"
  [ -n "$pids" ] && kill -9 $pids 2>/dev/null || true
}

wait_for_http() {
  # $1=URL $2=超时秒数；HTTP 返回（任意状态码）即视为就绪
  local url="$1" deadline=$(( $(date +%s) + $2 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local code
    if command -v curl >/dev/null 2>&1; then
      code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 2 "$url" 2>/dev/null || echo 000)"
    else
      code="$(wget -q -S --spider --timeout=2 "$url" 2>&1 | awk '/HTTP\//{print $2; exit}')"
      code="${code:-000}"
    fi
    [ "$code" != "000" ] && return 0
    sleep 1
  done
  return 1
}

BACKEND_PGID=""; FRONTEND_PGID=""
kill_group() {
  local pgid="$1"
  [ -z "$pgid" ] && return 0
  # 负数 PID 表示向整个进程组发信号，确保 npm 的 vite 子进程也一并退出
  kill -TERM "-$pgid" 2>/dev/null || true
  local i
  for i in $(seq 1 5); do
    sleep 1
    kill -0 "-$pgid" 2>/dev/null || return 0
  done
  kill -KILL "-$pgid" 2>/dev/null || true
}
cleanup() {
  trap - EXIT INT TERM
  kill_group "$FRONTEND_PGID"
  kill_group "$BACKEND_PGID"
}
interrupt() {
  echo   # 让出 Ctrl+C 所在行
  info "收到中断信号，正在同时停止前后端..."
  cleanup
  exit 130
}

cmd_dev() {
  check_prerequisites
  setup_backend
  setup_frontend
  install_git_hooks

  if port_in_use "$BACKEND_PORT"; then
    die "端口 $BACKEND_PORT 已被占用（后端需要该端口）。请先停止占用进程，或运行: bash scripts/dev.sh stop"
  fi
  if port_in_use "$FRONTEND_PORT"; then
    die "端口 $FRONTEND_PORT 已被占用（前端需要该端口）。请先停止占用进程，或运行: bash scripts/dev.sh stop"
  fi

  mkdir -p "$LOG_DIR"
  local backend_log="$LOG_DIR/backend.log" frontend_log="$LOG_DIR/frontend.log"
  : > "$backend_log"; : > "$frontend_log"

  info "启动后端 FastAPI (http://localhost:$BACKEND_PORT) ..."
  setsid bash -c '
    cd "'"$BACKEND_DIR"'"
    exec "'"$VENV_PY"'" -m uvicorn app.main:app --host 0.0.0.0 --port "'"$BACKEND_PORT"'"
  ' >"$backend_log" 2>&1 &
  BACKEND_PGID="$(ps -o pgid= -p $! | tr -d ' ')"

  info "启动前端 Vite (http://localhost:$FRONTEND_PORT) ..."
  setsid bash -c '
    cd "'"$FRONTEND_DIR"'"
    exec npm run dev
  ' >"$frontend_log" 2>&1 &
  FRONTEND_PGID="$(ps -o pgid= -p $! | tr -d ' ')"

  # 判断整个进程组是否还在（组长退出即视为该侧启动失败）
  backend_alive() { kill -0 "-$BACKEND_PGID" 2>/dev/null; }
  frontend_alive() { kill -0 "-$FRONTEND_PGID" 2>/dev/null; }

  trap cleanup EXIT
  trap interrupt INT TERM

  # 任一进程提前退出 -> 另一侧启动失败，立即给出明确结果
  sleep 2
  if ! backend_alive; then
    printf "${C_RED}✘ 后端启动失败，日志如下（完整日志: %s）:${C_RESET}\n" "$backend_log" >&2
    cat "$backend_log" >&2
    cleanup
    exit 1
  fi
  if ! frontend_alive; then
    printf "${C_RED}✘ 前端启动失败，日志如下（完整日志: %s）:${C_RESET}\n" "$frontend_log" >&2
    cat "$frontend_log" >&2
    cleanup
    exit 1
  fi

  info "等待服务就绪（最多 ${READY_TIMEOUT}s）..."
  local backend_ok=0 frontend_ok=0
  if wait_for_http "http://127.0.0.1:$BACKEND_PORT/docs" "$READY_TIMEOUT"; then backend_ok=1; fi
  if ! backend_alive; then
    printf "${C_RED}✘ 后端在启动过程中退出，日志如下（完整日志: %s）:${C_RESET}\n" "$backend_log" >&2
    cat "$backend_log" >&2
    cleanup
    exit 1
  fi
  if wait_for_http "http://127.0.0.1:$FRONTEND_PORT/" "$READY_TIMEOUT"; then frontend_ok=1; fi
  if ! frontend_alive; then
    printf "${C_RED}✘ 前端在启动过程中退出，日志如下（完整日志: %s）:${C_RESET}\n" "$frontend_log" >&2
    cat "$frontend_log" >&2
    cleanup
    exit 1
  fi

  echo
  [ "$backend_ok" = 1 ]  && ok "后端已就绪:  http://localhost:$BACKEND_PORT  (接口文档 /docs)"
  [ "$frontend_ok" = 1 ] && ok "前端已就绪:  http://localhost:$FRONTEND_PORT"
  if [ "$backend_ok" = 0 ] || [ "$frontend_ok" = 0 ]; then
    die "服务进程存活但健康检查超时，请查看 logs/ 下日志。"
  fi
  echo
  info "前后端运行中，日志: $LOG_DIR/{backend,frontend}.log；按 Ctrl+C 可同时停止两者。"

  # 任一进程运行期间保持前台；一侧意外退出即整体失败并停掉另一侧
  while backend_alive && frontend_alive; do
    sleep 2
  done
  if ! backend_alive; then
    printf "${C_RED}✘ 后端进程意外退出，最后 30 行日志:${C_RESET}\n" >&2
    tail -n 30 "$backend_log" >&2 || true
    cleanup
    exit 1
  fi
  if ! frontend_alive; then
    printf "${C_RED}✘ 前端进程意外退出，最后 30 行日志:${C_RESET}\n" >&2
    tail -n 30 "$frontend_log" >&2 || true
    cleanup
    exit 1
  fi
}

cmd_stop() {
  info "停止端口 $BACKEND_PORT / $FRONTEND_PORT 上的开发进程..."
  local stopped_any=0
  for port in "$BACKEND_PORT" "$FRONTEND_PORT"; do
    if port_in_use "$port"; then
      kill_port "$port"
      if port_in_use "$port"; then
        warn "端口 $port 上的进程未能停止（可能需要 root 权限），请手动结束。"
      else
        ok "端口 $port 已释放。"
        stopped_any=1
      fi
    fi
  done
  [ "$stopped_any" = 1 ] || ok "两个端口本来就没有开发进程在运行。"
}

# ----------------------------------------------------------------------------
# 提交前检查
# ----------------------------------------------------------------------------
cmd_check() {
  check_prerequisites
  local fail=0

  info "检查后端: Python 语法编译 + 应用可导入 + API 冒烟测试 ..."
  if "$PYTHON_BIN" -m compileall -q "$BACKEND_DIR/app"; then
    if venv_usable; then
      if ( cd "$BACKEND_DIR" && "$VENV_PY" -c 'from app.main import app' ) \
         && ( cd "$BACKEND_DIR" && "$VENV_PY" -m app.smoke_test ); then
        ok "后端检查通过。"
      else
        warn "后端检查失败（导入或 API 冒烟测试未通过）。"
        fail=1
      fi
    else
      warn "后端虚拟环境不存在，只做语法检查。执行 bash scripts/dev.sh setup 后可获得完整检查。"
    fi
  else
    warn "后端 Python 语法检查失败。"
    fail=1
  fi

  if [ -d "$FRONTEND_DIR/node_modules" ]; then
    info "检查前端: vue-tsc 类型检查 + vite 生产构建 ..."
    if ( cd "$FRONTEND_DIR" && npm run build ); then
      ok "前端类型检查与构建通过。"
    else
      warn "前端构建/类型检查失败。"
      fail=1
    fi
  else
    warn "前端 node_modules 不存在，跳过类型检查与构建。执行 bash scripts/dev.sh setup 后可获得完整检查。"
  fi

  echo
  if [ "$fail" = 0 ]; then
    ok "全部检查通过。"
  else
    die "检查未通过，请修复上述问题后再提交（紧急情况下可用 git commit --no-verify 跳过）。"
  fi
}

case "${1:-dev}" in
  setup) cmd_setup ;;
  dev|start) cmd_dev ;;
  stop) cmd_stop ;;
  check) cmd_check ;;
  *)
    echo "用法: bash scripts/dev.sh [setup|dev|check|stop]" >&2
    exit 2
    ;;
esac
