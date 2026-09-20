"""离线冒烟测试：不启动服务，直接调用优化接口。

覆盖四种算法在多个测试函数上的组合：
1. 算法能正常跑完且返回结构正确；
2. 返回结果用严格 JSON 序列化一遍（allow_nan=False，禁止 NaN/Infinity），
   用来拦截 numpy 标量、数值发散产生 NaN 这类运行时错误。
由 scripts/dev.sh check 调用：python -m app.smoke_test
"""
import json
import warnings

from .main import OptimizationRequest, optimize

# (算法, 测试函数) 组合；含 rosenbrock 这种容易在大步长下数值发散的情况
CASES = [
    ("gradient_descent", "sphere"),
    ("gradient_descent", "rosenbrock"),
    ("newton", "sphere"),
    ("conjugate_gradient", "sphere"),
    ("conjugate_gradient", "rosenbrock"),
    ("simulated_annealing", "rastrigin"),
]


def reject_nonfinite(val):
    raise ValueError(f"JSON 中出现非法数值: {val}")


def main() -> None:
    for algorithm, function_id in CASES:
        req = OptimizationRequest(algorithm=algorithm, functionId=function_id, iterations=10)
        # 发散用例预期会产生 numpy 溢出告警，测试只关心返回的 JSON 是否合法
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")
            body = optimize(req).body.decode("utf-8")
        result = json.loads(body, parse_constant=reject_nonfinite)
        assert len(result["path"]) == 11, f"{algorithm}: 路径点数不符合预期"
        assert isinstance(result["converged"], bool)
        print(f"  {algorithm:20s} @ {function_id:10s} OK, finalValue={result['finalValue']}, "
              f"converged={result['converged']}")
    print(f"后端 API 冒烟测试通过（{len(CASES)} 个算法/函数组合均可执行且返回合法 JSON）。")


if __name__ == "__main__":
    main()
