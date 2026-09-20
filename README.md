# 数值优化算法逐帧可视化教学平台

基于 Vue 3 + FastAPI 的优化算法交互式教学工具，支持梯度下降/牛顿法/共轭梯度/模拟退火四种算法的 2D 等高线与 3D 曲面双视图可视化。

## 目标用户
机器学习方向学生、优化理论研究者、算法教学者

## 技术栈与运行环境（版本已固定）
| 部分 | 技术 | 运行环境要求 |
| --- | --- | --- |
| 前端 | Vue 3 + TypeScript + Vite + Pinia + Element Plus + ECharts + Three.js | **Node.js 20.x**（见 `.nvmrc`）+ npm 10 |
| 后端 | Python FastAPI + NumPy | **Python 3.11.x**（唯一支持版本，3.9/3.10/3.12+ 未验证） |

- 前端依赖精确版本固定在 `frontend/package.json`，完整解析结果锁定在 `frontend/package-lock.json`（该锁文件已纳入版本库，勿删除）。
- 后端直接依赖见 `backend/requirements.txt`，完整传递依赖锁定在 `backend/requirements.lock`。

## 快速开始（本地开发）

前置条件：已安装 Python 3.11、Node.js 20、git。

```bash
# 一键安装前后端全部依赖（幂等，可反复执行；也可直接执行下一步，会自动先装依赖）
make setup        # 等价于 bash scripts/dev.sh setup

# 同时启动前端（http://localhost:3000）和后端（http://localhost:8000，接口文档 /docs）
make dev          # 等价于 bash scripts/dev.sh dev；Ctrl+C 同时停止两者
```

启动后打开 <http://localhost:3000>，前端 `/api` 请求会自动代理到后端 8000 端口，无需额外配置。

其他命令：

```bash
make check   # 提交前检查：后端语法/导入/API 冒烟测试 + 前端 vue-tsc 类型检查与生产构建
make stop    # 释放 8000/3000 端口上的开发进程
```

三种典型场景的结果说明，以及故障排查（如系统 Python 不带 pip、跨平台残留环境等），
请参阅 **[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)**（与本说明保持一致的详细开发文档）。

提交前检查会在 `make setup` 时自动安装为 git pre-commit 钩子；紧急情况可用 `git commit --no-verify` 跳过。

## 核心功能
1. 四种优化算法实现：梯度下降、牛顿法、共轭梯度、模拟退火
2. 2D 函数等高线绘制（Canvas）+ 3D 曲面（Three.js）双视图同步渲染
3. 步长、动量、初始点等参数实时调节
4. 优化路径逐帧动画播放，显示迭代收敛轨迹
5. 预设 6 种测试函数（Rosenbrock/Himmelblau/Rastrigin/Sphere/Beale/Booth）
6. 收敛曲线（ECharts）显示每步函数值下降

## 项目结构
```
solo-6600050/
├── Makefile                    # setup / dev / check / stop 命令入口
├── scripts/
│   ├── dev.sh                  # 一键安装、启动、检查、停止的具体逻辑
│   └── pre-commit              # 提交前钩子模板（setup 时安装到 .git/hooks/）
├── docs/
│   └── DEVELOPMENT.md          # 详细本地开发流程与故障排查
├── .nvmrc                      # Node 版本（20.20.2）
├── frontend/                   # Vue 3 + TypeScript + Vite
│   ├── package.json            # 前端依赖（精确版本）
│   ├── package-lock.json       # 前端依赖锁文件（纳入版本库）
│   └── src/components/
│       ├── ContourPlot.vue       # Canvas 2D 等高线
│       ├── Surface3D.vue         # Three.js 3D 曲面
│       ├── ControlPanel.vue      # 参数面板
│       └── ConvergenceChart.vue  # ECharts 收敛曲线
└── backend/                    # FastAPI + NumPy（Python 3.11）
    ├── requirements.txt        # 后端直接依赖（精确版本）
    ├── requirements.lock       # 后端完整依赖锁文件
    └── app/
        ├── main.py             # FastAPI 应用与四种算法实现
        └── smoke_test.py       # 离线 API 冒烟测试（check 时运行）
```
