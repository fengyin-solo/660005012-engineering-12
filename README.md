# 数值优化算法逐帧可视化教学平台

基于Vue 3 + FastAPI的优化算法交互式教学工具，支持梯度下降/牛顿法/共轭梯度/模拟退火四种算法的2D等高线与3D曲面双视图可视化。

## 目标用户
机器学习方向学生、优化理论研究者、算法教学者

## 技术栈
- 前端: Vue 3 + TypeScript + Vite + Pinia + Element Plus + ECharts + Three.js
- 后端: Python FastAPI + NumPy

## 环境要求

| 组件 | 版本要求 | 说明 |
| --- | --- | --- |
| Node.js | >= 18（推荐 20 LTS） | 含 npm，前端构建与开发服务器 |
| Python | >= 3.9（推荐 3.11） | 后端运行环境，仅需要标准库中的 `venv` |
| 操作系统 | macOS / Linux / Windows | Windows 推荐在 Git Bash 或 WSL 中执行脚本 |

依赖版本均已固定：前端见 `frontend/package.json` 与提交到仓库的 `frontend/package-lock.json`，后端见 `backend/requirements.txt`，换机器安装结果一致。

## 快速开始

```bash
# 1. 一键安装前后端依赖（幂等，可随时重复执行；下载缓存放在 .cache/）
./scripts/install.sh

# 2. 一条命令同时启动前后端
./scripts/dev.sh
```

启动成功后：

- 前端页面：http://127.0.0.1:3000 （Vite，固定端口，占用即报错）
- 后端接口：http://127.0.0.1:8000 （接口文档 /docs）
- 前端通过 `/api` 代理转发到后端，无需处理跨域
- 按 `Ctrl-C` 同时停止两个服务；运行日志在 `logs/` 目录

> 没有 bash 环境时可用等价的 npm/pip 手动命令，见 [DEVELOPMENT.md](./DEVELOPMENT.md)。

## 常用命令

| 命令 | 作用 |
| --- | --- |
| `./scripts/install.sh` | 安装/校验前后端依赖（已装则跳过，断网可命中缓存） |
| `./scripts/install.sh --force` | 忽略已装状态，前后端强制重装 |
| `./scripts/dev.sh` | 先校验依赖，再同时启动前后端 |
| `./scripts/dev.sh --skip-install` | 跳过依赖检查直接启动（已确认装好时更快） |
| `./scripts/check.sh` | 前端类型检查+构建、后端语法编译+导入冒烟 |
| `make install` / `make dev` / `make check` | 上述操作的 make 快捷方式 |

## 提交前检查

`install.sh` 会自动安装 git pre-commit 钩子（源文件 `scripts/pre-commit`），每次 `git commit` 前自动运行 `scripts/check.sh`：前端执行 `vue-tsc` 类型检查与 Vite 生产构建，后端做全量语法编译和应用导入检查，任一项失败都会阻止提交。仅改动文档等不相关文件时会自动跳过，不会浪费构建时间。

## 三种执行场景的预期结果

1. **首次安装**：创建后端 `.venv`（系统 venv 缺 pip 时会自动用 `get-pip.py` 引导）、`npm ci` 严格按 lockfile 安装前端，结束后打印启动方式。
2. **依赖已存在时重复执行**：逐项校验前端平台原生依赖、后端固定版本，全部满足时秒级跳过；发现损坏（如把 macOS 上装的 `node_modules`/`.venv` 拷到 Linux）会自动重建。
3. **某一侧启动失败**（如端口 3000/8000 被占用、依赖导入失败）：脚本以非零状态码退出，打印对应侧日志末尾并指明完整日志位置，另一侧进程会被一并清理。

更多排查步骤见 [DEVELOPMENT.md](./DEVELOPMENT.md) 的"常见问题"。

## 核心功能
1. 四种优化算法实现：梯度下降、牛顿法、共轭梯度、模拟退火
2. 2D函数等高线绘制(Canvas) + 3D曲面(Three.js)双视图同步渲染
3. 步长、动量、初始点等参数实时调节
4. 优化路径逐帧动画播放，显示迭代收敛轨迹
5. 预设6种测试函数(Rosenbrock/Himmelblau/Rastrigin/Sphere/Beale/Booth)
6. 收敛曲线(ECharts)显示每步函数值下降

## 项目结构
```
solo-6600050/
├── scripts/
│   ├── install.sh     # 一键安装前后端依赖（幂等）
│   ├── dev.sh         # 同时启动前后端开发服务
│   ├── check.sh       # 构建与基本检查（pre-commit 也调用它）
│   └── pre-commit     # git 钩子源文件，由 install.sh 安装
├── frontend/          Vue 3 + TypeScript + Vite
│   ├── package.json   # 前端固定版本（与 package-lock.json 同步提交）
│   └── src/components/
│       ├── ContourPlot.vue       # Canvas 2D等高线
│       ├── Surface3D.vue         # Three.js 3D曲面
│       ├── ControlPanel.vue      # 参数面板
│       └── ConvergenceChart.vue  # ECharts收敛曲线
└── backend/           FastAPI + NumPy
    ├── requirements.txt  # 后端固定版本
    └── app/main.py
```
