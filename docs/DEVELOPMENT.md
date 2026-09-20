# 本地开发流程说明

本文档与根目录 `README.md` 的「快速开始」保持一致，补充首次安装背后的行为约定、
三种执行结果以及常见故障排查。命令入口只有一个：`scripts/dev.sh`（`make` 只是它的简写封装）。

## 1. 环境要求

| 组件 | 要求版本 | 说明 |
| --- | --- | --- |
| Python | **3.11.x** | 后端唯一支持的运行环境；脚本会检测，版本不符直接报错退出 |
| Node.js | **20.x** | 仓库根目录提供 `.nvmrc`，可用 `nvm use` 切换 |
| npm | 随 Node 20 提供（10.x） | — |
| git | 任意较新版本 | 用于安装 pre-commit 钩子 |
| 操作系统 | macOS / Linux | Windows 请使用 WSL |

后端**不再支持 Python 3.9**：旧的 `backend/.venv`（指向其他机器路径、3.9 解释器）
在首次运行新脚本时会被识别为不可用并自动重建，无需手动处理。

## 2. 命令一览

| 命令 | 作用 |
| --- | --- |
| `make setup`（`bash scripts/dev.sh setup`） | 一键安装前后端依赖并安装 pre-commit 钩子，可反复执行 |
| `make dev`（`bash scripts/dev.sh dev`） | 先确保依赖就绪，再同时启动前后端；`Ctrl+C` 同时停止 |
| `make check`（`bash scripts/dev.sh check`） | 后端语法/导入/API 冒烟测试 + 前端类型检查与生产构建 |
| `make stop`（`bash scripts/dev.sh stop`） | 停止占用 8000/3000 端口的开发进程 |

启动成功后的访问地址：

- 前端：<http://localhost:3000>
- 后端：<http://localhost:8000>（接口文档 <http://localhost:8000/docs>）
- 前端 `/api/*` 请求经 Vite 代理转发到 `127.0.0.1:8000`（见 `frontend/vite.config.ts`，
  两端均显式绑定 IPv4 回环地址，避免部分机器上 `localhost` 只解析到 IPv6 导致连不上）

## 3. 三种执行场景的明确结果

### 场景 A：首次安装（新机器 / 新人接手）

1. 校验 Python 3.11、Node 20、npm、git 是否存在，缺任意一个都会**明确报错并指出安装方式**。
2. 删除不可用的旧环境（其他操作系统/其他 Python 版本创建的 `.venv`、缺原生二进制的
   `node_modules`），随后：
   - 创建 `backend/.venv`；若系统 Python 的 venv 不带 pip（Debian/Ubuntu 常见），
     自动通过 `get-pip.py` 引导，**不污染系统 Python**；
   - 按 `backend/requirements.lock` 安装后端依赖；
   - 前端按 `package-lock.json` 执行 `npm ci` 严格安装。
3. 安装 pre-commit 钩子。
4. 全部成功时输出 `✔ 全部就绪`；任何一步失败都打印原因并以非零码退出，不会留下半成品状态。

### 场景 B：依赖已存在时重复执行

脚本用「依赖清单哈希 + 安装标记」判断是否需要安装（标记位于 `.cache/dev/`）：

- 两侧均未变化时：约 0.3 秒内输出两个 `跳过`，不访问网络；
- 只改了一侧的清单：仅重装该侧，另一侧跳过；
- 锁文件与 `package.json` 不同步导致 `npm ci` 失败时，自动回退 `npm install` 并更新锁文件。

### 场景 C：某一侧启动失败

- 后端先启动、前端后启动；启动后对两端做 HTTP 就绪探测（最长 60 秒）。
- 任一侧进程提前退出或健康检查超时：**打印失败侧的完整/尾部日志、日志文件路径，
  以退出码 1 结束**，并自动终止另一侧（两侧各自运行在独立进程组，
  连 npm 的 vite 孙进程也会一并回收，不会残留占用端口的孤儿进程）。
- 运行期间任一侧意外崩溃，前台脚本同样以退出码 1 结束并打印最后 30 行日志。

## 4. 版本锁定与缓存

- 前端：`package.json` 中所有依赖为**精确版本号**（无 `^`/`~`），配合已入库的
  `package-lock.json`；`frontend/.npmrc` 配置了 `save-exact=true`（以后 `npm install
  <pkg>` 默认也写精确版本）与重试参数。
- 后端：`requirements.txt` 列直接依赖，`requirements.lock` 锁定全部传递依赖。
  更新依赖的流程：改 `requirements.txt` → 在虚拟环境中安装验证 → `pip freeze` 更新
  `requirements.lock` → 两个文件一起提交。
- 缓存：
  - pip 下载缓存固定在项目内的 `.pip-cache/`（已 gitignore），可离线复用；
  - npm 使用本机 npm 缓存，且 `node_modules` 完整时直接跳过安装。

## 5. 提交前自动检查

`make setup` 会把 `scripts/pre-commit` 安装为 `.git/hooks/pre-commit`，每次 `git commit`
自动执行 `make check`，内容包括：

1. 后端：`compileall` 语法编译 + 应用可导入 + `app/smoke_test.py` 离线冒烟测试
   （四种算法 × 多个测试函数，响应必须能通过 `allow_nan=False` 的严格 JSON 序列化，
   防止 numpy 标量、数值发散产生 NaN 等问题流入前端）；
2. 前端：`vue-tsc` 类型检查 + `vite build` 生产构建。

任何一项失败都会阻止提交；紧急情况下可用 `git commit --no-verify` 临时跳过。
钩子模板在版本库中，若你已有自定义 pre-commit，脚本不会覆盖，只会提示手动接入。

## 6. 故障排查

| 现象 | 原因与处理 |
| --- | --- |
| `未找到 Python 3.11` | 安装 Python 3.11（macOS: `brew install python@3.11`；Ubuntu: `apt install python3.11 python3.11-venv`） |
| `venv 中没有 pip，使用 get-pip.py 引导` 后失败 | 网络无法访问 PyPI，检查代理后重试；引导只在项目 venv 内进行 |
| `检测到已有的 .venv 不可用...将删除重建` | 正常现象：旧环境是其他操作系统/Python 版本创建的（如仓库初始提交中的 macOS 3.9 venv） |
| `检测到已有的 node_modules 不完整或来自其他平台` | 正常现象：跨平台复制过目录、缺少 rollup/esbuild 原生二进制时会自动重装 |
| 端口 8000/3000 被占用 | `make stop` 按端口释放（无需 lsof/fuser，脚本会通过 `/proc` 扫描）；仍失败请手动结束占用进程 |
| `npm ci 失败...改用 npm install` | `package.json` 与锁文件不同步，脚本会自动更新锁文件；请把更新后的 `package-lock.json` 一并提交 |
| 前端请求 `/api` 报 500/解析失败 | 先跑 `make check`；后端对数值发散（NaN/Inf）会返回 `null` 而非非法 JSON，属预期保护 |
| 改完代码想只跑检查不启动服务 | `make check` |

## 7. 运行期产物（均已 gitignore）

- `backend/.venv/`：后端虚拟环境
- `frontend/node_modules/`、`frontend/dist/`：前端依赖与构建产物
- `.pip-cache/`：pip 下载缓存
- `.cache/dev/`：安装状态标记与 `get-pip.py` 引导脚本
- `logs/backend.log`、`logs/frontend.log`：`make dev` 的两侧运行日志
