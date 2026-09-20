# 本地开发指南

本文件是 README「快速开始」的展开说明，命令、端口、版本要求与 README 保持一致；如两者出现分歧，以两份文档同时更新为准。

## 1. 环境要求

| 组件 | 版本要求 | 检查命令 |
| --- | --- | --- |
| Node.js | >= 18（推荐 20 LTS），自带 npm | `node -v` |
| Python | >= 3.9（推荐 3.11），含标准库 `venv` | `python3 -V` |
| 操作系统 | macOS / Linux；Windows 用 Git Bash 或 WSL | — |

> Python 后端必须使用 3.9 及以上版本。脚本创建的是项目内独立虚拟环境 `backend/.venv`，不污染系统 Python；不需要也不建议全局安装 FastAPI。

## 2. 一键安装

```bash
./scripts/install.sh
```

脚本是**幂等**的，首次安装与重复执行都安全：

| 场景 | 行为与结果 |
| --- | --- |
| 首次安装 | 前端 `npm ci`（严格按 `frontend/package-lock.json` 安装到 `frontend/node_modules`）；后端创建 `backend/.venv` 并安装 `backend/requirements.txt`；安装 git pre-commit 钩子；结束时打印下一步命令，退出码 0 |
| 重复执行、依赖完好 | 校验通过后前后端均跳过安装，秒级结束 |
| 依赖损坏 / 跨机器拷贝 | 识别后自动重建：前端检查 rollup 平台原生模块（macOS 上装的 `node_modules` 拷到 Linux 会被判定为损坏），后端检查 `.venv` 的 Python 解释器是否指向当前机器、pip 与固定版本依赖是否可用 |
| 想强制重装 | `./scripts/install.sh --force` |
| 任一安装步骤失败 | 打印具体失败环节（前端 npm / 后端 pip / pip 引导），以非零退出码结束，不会留下"装了一半还提示成功"的状态 |

### 缓存位置

- npm 缓存：`.cache/npm`（通过 `npm ci --cache` 指定，不依赖全局 npm 缓存）
- pip 缓存：`.cache/pip`（通过 `pip --cache-dir` 指定）
- 两者都在 `.gitignore` 中；离线或弱网环境下重复安装可直接命中缓存

后端虚拟环境如果系统自带的 `python3 -m venv` 没有 pip（Debian/Ubuntu 未装 `python3-venv` 时常见，且没有 root 权限装不了），脚本会先用 `--without-pip` 建环境，再用官方 `get-pip.py` 引导，无需 sudo。

## 3. 启动开发环境

```bash
./scripts/dev.sh            # 先自动跑一次幂等安装，再启动
./scripts/dev.sh --skip-install   # 已确认装齐时，跳过安装直接启动
```

启动约定：

- 后端：FastAPI / uvicorn 监听 `http://127.0.0.1:8000`，接口文档 `http://127.0.0.1:8000/docs`
- 前端：Vite 监听 `http://127.0.0.1:3000`，`vite.config.ts` 设了 `strictPort: true`，端口被占用会直接失败而不是悄悄换端口
- 前端 `/api/*` 请求经 Vite 代理转发到 `http://127.0.0.1:8000`
- 两路日志带 `[backend]` / `[frontend]` 前缀合并输出，同时写入 `logs/backend.log`、`logs/frontend.log`
- **两个端口都连通才提示启动成功**；任一侧启动失败或运行中途退出，脚本打印该侧最后 30 行日志、以退出码 1 结束，并清理另一侧进程
- `Ctrl-C` 同时关闭前后端（按进程组清理，不留孤儿进程）

## 4. 手动检查与构建

```bash
./scripts/check.sh             # 检查全部
./scripts/check.sh --staged    # 只检查暂存区涉及的一侧（钩子用）
```

检查内容：

1. 前端：`npm run build`（`vue-tsc` 类型检查 + `vite build` 生产构建），产物在 `frontend/dist`
2. 后端：`compileall` 全量语法编译 + `from app.main import app` 导入冒烟（能挡住语法错误、缺依赖、循环导入等明显问题）

## 5. 提交前检查钩子

`./scripts/install.sh` 会把 `scripts/pre-commit` 复制为 `.git/hooks/pre-commit`（钩子不进仓库的常规管理路径，因此以脚本文件为源，重复安装会自动更新）。

- `git commit` 时自动执行 `./scripts/check.sh --staged`
- 暂存内容只涉及前端 → 只跑前端构建；只涉及后端 → 只跑后端检查；涉及 `scripts/` → 两侧都查；纯文档改动直接放行
- 检查失败（退出码非 0）会阻止提交，可按提示修复后重新 `git add` / `git commit`
- 紧急情况下可用 `git commit --no-verify` 跳过，但不推荐

## 6. 不使用脚本时的等价手动命令

脚本只是把以下步骤串起来并做了幂等与失败处理，等价的手动流程为：

```bash
# 前端
cd frontend
npm ci --cache ../.cache/npm
npm run dev      # 或 npm run build

# 后端
cd backend
python3 -m venv .venv
.venv/bin/python -m pip install --cache-dir ../.cache/pip -r requirements.txt
.venv/bin/python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Windows PowerShell 下激活虚拟环境用 `backend\.venv\Scripts\Activate.ps1`；其余命令相同。

## 7. 常见问题

**端口被占用（`address already in use` / `Port 3000 is already in use`）**
停掉占用进程，或在另一个终端先处理；脚本检测到该错误会以退出码 1 结束并指出是哪一侧。

**换了机器（如 macOS → Linux）后前端构建报 `Cannot find module '@rollup/rollup-linux-...'`**
说明 `node_modules` 是在别的操作系统上安装的。直接重跑 `./scripts/install.sh`，检测到平台不匹配会自动重装；也可手动删除 `frontend/node_modules` 后再装。

**后端 `.venv` 里的 python 指向旧机器路径（如 `/Library/...` 或 `/Users/...`）**
重跑 `./scripts/install.sh`，会自动删除并重建失效的虚拟环境。

**提示 `ensurepip is not available`**
无需 sudo：安装脚本会自动改用 `get-pip.py` 引导。手动处理时可执行
`python3 -m venv --without-pip backend/.venv && curl -sSL https://bootstrap.pypa.io/get-pip.py | backend/.venv/bin/python -`。

**pre-commit 钩子提示依赖未安装**
钩子依赖安装好的环境运行检查，先执行一次 `./scripts/install.sh` 再提交。
