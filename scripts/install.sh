#!/usr/bin/env bash
# 一键安装前后端本地开发环境（幂等：可重复执行）。
# 用法: ./scripts/install.sh [--force]
#   --force  忽略缓存与已安装状态，前后端均重新安装
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_DIR="$ROOT_DIR/backend"
CACHE_DIR="$ROOT_DIR/.cache"
NPM_CACHE_DIR="$CACHE_DIR/npm"
PIP_CACHE_DIR="$CACHE_DIR/pip"
VENV_DIR="$BACKEND_DIR/.venv"

FORCE=0
[[ "${1:-}" == "--force" ]] && FORCE=1

# ---- 输出辅助 --------------------------------------------------------------
if [[ -t 1 ]]; then
  C_BLUE=$'\033[1;34m'; C_GREEN=$'\033[1;32m'; C_YELLOW=$'\033[1;33m'
  C_RED=$'\033[1;31m'; C_RESET=$'\033[0m'
else
  C_BLUE=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_RESET=""
fi
info()  { printf '%s[install]%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
ok()    { printf '%s[install]%s %s\n' "$C_GREEN"  "$C_RESET" "$*"; }
warn()  { printf '%s[install]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
die()   { printf '%s[install] 错误:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# ---- 环境要求 --------------------------------------------------------------
info "检查运行环境 ..."
command -v node >/dev/null 2>&1 || die "未找到 node，请先安装 Node.js >= 18（推荐使用 nvm）。"
NODE_MAJOR="$(node -p 'process.versions.node.split(".")[0]')"
[[ "$NODE_MAJOR" -ge 18 ]] || die "Node.js 版本过低（当前 $(node -v)），需要 >= 18。"
command -v npm >/dev/null 2>&1 || die "未找到 npm，请随 Node.js 一起安装。"
command -v python3 >/dev/null 2>&1 || die "未找到 python3，请先安装 Python >= 3.9。"
PY_MAJOR_MINOR="$(python3 -c 'import sys;print("%d.%d"%sys.version_info[:2])')"
PY_OK="$(python3 -c 'import sys;print(1 if sys.version_info[:2]>=(3,9) else 0)')"
[[ "$PY_OK" == "1" ]] || die "Python 版本过低（当前 $PY_MAJOR_MINOR），需要 >= 3.9。"
info "Node $(node -v) / npm $(npm -v) / Python $PY_MAJOR_MINOR"
mkdir -p "$NPM_CACHE_DIR" "$PIP_CACHE_DIR"

# ---- 前端 ------------------------------------------------------------------
# node_modules 完好的判据：
#   1) .bin/vue-tsc 存在
#   2) 当前平台对应的 rollup 原生可选依赖可解析（换操作系统后该检查会失败，
#      例如在 macOS 安装的 node_modules 拷到 Linux）
frontend_ok() {
  [[ -x "$FRONTEND_DIR/node_modules/.bin/vue-tsc" ]] || return 1
  # rollup 的原生可选依赖与操作系统/架构绑定；在 macOS 安装的 node_modules
  # 拷到 Linux 时这一步会抛错（以此识别"跨平台残留"的依赖目录）。
  ( cd "$FRONTEND_DIR" && node -e "require('./node_modules/rollup/dist/native.js')" ) \
    >/dev/null 2>&1 || return 1
  return 0
}

install_frontend() {
  info "安装前端依赖（npm ci，严格按 package-lock.json）..."
  ( cd "$FRONTEND_DIR" && npm ci --cache "$NPM_CACHE_DIR" --prefer-offline ) \
    || die "前端依赖安装失败，请检查网络或 registry 配置（npm config get registry）。"
}

if [[ "$FORCE" == "1" ]]; then
  info "--force：重新安装前端依赖"
  install_frontend
elif frontend_ok; then
  ok "前端依赖已存在且与当前平台匹配，跳过（用 --force 可强制重装）"
else
  if [[ -d "$FRONTEND_DIR/node_modules" ]]; then
    warn "前端 node_modules 缺失或与当前操作系统/架构不匹配，重新安装"
  else
    info "首次安装前端依赖"
  fi
  install_frontend
fi
ok "前端依赖就绪"

# ---- 后端 ------------------------------------------------------------------
venv_python_ok() {
  [[ -x "$VENV_DIR/bin/python" ]] || return 1
  "$VENV_DIR/bin/python" -c 'import sys; sys.exit(0 if sys.version_info[:2]>=(3,9) else 1)' \
    >/dev/null 2>&1 || return 1
  "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1 || return 1
  return 0
}

backend_deps_ok() {
  # requirements.txt 中所有固定版本都已可导入，即视为已安装
  "$VENV_DIR/bin/python" - "$BACKEND_DIR/requirements.txt" <<'PY'
import importlib.metadata as md
import sys

ok = True
with open(sys.argv[1], encoding="utf-8") as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "==" not in line:
            ok = False
            continue
        name, version = line.split("==", 1)
        try:
            if md.version(name) != version:
                ok = False
        except md.PackageNotFoundError:
            ok = False
sys.exit(0 if ok else 1)
PY
}

if [[ "$FORCE" == "1" ]] || ! venv_python_ok; then
  if [[ -d "$VENV_DIR" ]]; then
    warn "发现不可用的 .venv（可能是在其他操作系统上创建的），重新创建"
    rm -rf "$VENV_DIR"
  else
    info "创建后端虚拟环境 ($VENV_DIR)"
  fi
  # 部分发行版的 venv 不带 ensurepip，先建无 pip 的 venv 再引导 pip
  python3 -m venv "$VENV_DIR" 2>/dev/null || python3 -m venv --without-pip "$VENV_DIR"
  if ! "$VENV_DIR/bin/python" -m pip --version >/dev/null 2>&1; then
    info "venv 中没有 pip，使用 get-pip.py 引导 ..."
    bootstrap="$(mktemp -t get-pip.XXXXXX.py)"
    curl -fsSL https://bootstrap.pypa.io/get-pip.py -o "$bootstrap" \
      || die "下载 get-pip.py 失败，请检查网络。"
    "$VENV_DIR/bin/python" "$bootstrap" || die "pip 引导失败。"
    rm -f "$bootstrap"
  fi
fi
ok "后端虚拟环境就绪（Python $("$VENV_DIR/bin/python" -c 'import sys;print("%d.%d.%d"%sys.version_info[:3])')）"

if [[ "$FORCE" == "1" ]] || ! backend_deps_ok; then
  info "安装后端依赖（pip install -r requirements.txt，使用本地缓存目录）..."
  "$VENV_DIR/bin/python" -m pip install \
    --cache-dir "$PIP_CACHE_DIR" \
    -r "$BACKEND_DIR/requirements.txt" \
    || die "后端依赖安装失败，请检查网络。"
else
  ok "后端依赖已与 requirements.txt 一致，跳过（用 --force 可强制重装）"
fi

# 导入冒烟检查：避免装出一个无法启动的环境
"$VENV_DIR/bin/python" -c "import fastapi, uvicorn, numpy" \
  || die "后端依赖冒烟导入失败，请用 --force 重新安装。"
ok "后端依赖就绪"

# ---- git 提交前检查钩子 -----------------------------------------------------
HOOK_SRC="$ROOT_DIR/scripts/pre-commit"
HOOK_DST="$ROOT_DIR/.git/hooks/pre-commit"
if [[ -d "$ROOT_DIR/.git" ]]; then
  if [[ ! -f "$HOOK_DST" ]] || ! cmp -s "$HOOK_SRC" "$HOOK_DST"; then
    cp "$HOOK_SRC" "$HOOK_DST"
    chmod +x "$HOOK_DST"
    ok "已安装/更新 pre-commit 钩子（提交前自动运行 scripts/check.sh）"
  else
    ok "pre-commit 钩子已是最新"
  fi
fi

cat <<EOF

${C_GREEN}安装完成。${C_RESET}
  启动开发环境:  ./scripts/dev.sh
  手动检查:      ./scripts/check.sh
  强制重装:      ./scripts/install.sh --force
EOF
