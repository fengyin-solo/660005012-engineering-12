#!/usr/bin/env bash
# 提交前 / 手动执行的基本检查：前端类型检查 + 构建，后端语法编译 + 导入冒烟。
#
# 用法:
#   ./scripts/check.sh              # 检查前后端
#   ./scripts/check.sh --staged     # 仅检查 git 暂存区涉及的一侧（供 pre-commit 钩子调用）
#
# 退出码: 0 全部通过；非 0 存在错误（会阻止 git commit）。
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_DIR="$ROOT_DIR/backend"
VENV_DIR="$BACKEND_DIR/.venv"

CHECK_FRONTEND=1
CHECK_BACKEND=1
if [[ "${1:-}" == "--staged" ]]; then
  CHECK_FRONTEND=0
  CHECK_BACKEND=0
  if ! git -C "$ROOT_DIR" diff --cached --name-only --quiet -- frontend; then CHECK_FRONTEND=1; fi
  if ! git -C "$ROOT_DIR" diff --cached --name-only --quiet -- backend;  then CHECK_BACKEND=1;  fi
  # 基础设施脚本变更时两侧都查，保证脚本改动不会被漏检
  if ! git -C "$ROOT_DIR" diff --cached --name-only --quiet -- scripts; then
    CHECK_FRONTEND=1
    CHECK_BACKEND=1
  fi
fi

if [[ -t 1 ]]; then
  C_GREEN=$'\033[1;32m'; C_RED=$'\033[1;31m'; C_BLUE=$'\033[1;34m'; C_RESET=$'\033[0m'
else
  C_GREEN=""; C_RED=""; C_BLUE=""; C_RESET=""
fi
info() { printf '%s[check]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }

FAILURES=()

# ---- 前端：vue-tsc 类型检查 + vite 生产构建 ---------------------------------
if [[ "$CHECK_FRONTEND" == "1" ]]; then
  info "前端：类型检查 + 构建 (npm run build)"
  if [[ ! -d "$FRONTEND_DIR/node_modules" ]]; then
    printf '%s[check] 错误:%s 前端依赖未安装，请先运行 ./scripts/install.sh\n' "$C_RED" "$C_RESET" >&2
    FAILURES+=("前端：依赖未安装")
  elif ( cd "$FRONTEND_DIR" && npm run build ); then
    printf '%s[check]%s 前端构建通过\n' "$C_GREEN" "$C_RESET"
  else
    FAILURES+=("前端：类型检查或构建失败")
  fi
fi

# ---- 后端：全量语法编译 + 应用导入冒烟 -------------------------------------
if [[ "$CHECK_BACKEND" == "1" ]]; then
  info "后端：语法编译 + 导入检查"
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    printf '%s[check] 错误:%s 后端虚拟环境不存在，请先运行 ./scripts/install.sh\n' "$C_RED" "$C_RESET" >&2
    FAILURES+=("后端：虚拟环境不存在")
  else
    BACKEND_OK=1
    "$VENV_DIR/bin/python" -m compileall -q "$BACKEND_DIR/app" || BACKEND_OK=0
    ( cd "$BACKEND_DIR" && "$VENV_DIR/bin/python" -c "from app.main import app" ) || BACKEND_OK=0
    if [[ "$BACKEND_OK" == "1" ]]; then
      printf '%s[check]%s 后端检查通过\n' "$C_GREEN" "$C_RESET"
    else
      FAILURES+=("后端：语法或导入检查失败")
    fi
  fi
fi

# ---- 汇总 ------------------------------------------------------------------
if [[ "${#FAILURES[@]}" -gt 0 ]]; then
  printf '\n%s检查未通过：%s\n' "$C_RED" "$C_RESET" >&2
  for f in "${FAILURES[@]}"; do printf '  - %s\n' "$f" >&2; done
  exit 1
fi
printf '%s[check] 全部检查通过%s\n' "$C_GREEN" "$C_RESET"
