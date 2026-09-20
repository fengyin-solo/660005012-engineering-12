# 本地开发常用命令封装，具体逻辑见 scripts/dev.sh
.PHONY: help setup dev stop check

help: ## 显示可用命令
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  make \033[36m%-8s\033[0m %s\n", $$1, $$2}'

setup: ## 一键安装前后端依赖（幂等，可重复执行）
	bash scripts/dev.sh setup

dev: ## 安装依赖（如需要）并同时启动前后端
	bash scripts/dev.sh dev

check: ## 提交前检查：后端语法/导入 + 前端类型检查/构建
	bash scripts/dev.sh check

stop: ## 停止占用 8000/3000 端口的开发进程
	bash scripts/dev.sh stop
