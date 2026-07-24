TORCHAIR=/usr/local/python3.12.13/lib/python3.12/site-packages/torch_npu/dynamo/npugraph_ex

# 1. acl_graph 的 __call__ 和 compile 全貌（录制/回放的核心逻辑）
sed -n '780,1000p' $TORCHAIR/_acl_concrete_graph/acl_graph.py

# 2. 它如何处理图里的自定义 op（fallback/eager/custom 关键字）
grep -n -i "fallback\|custom\|eager\|call_function\|OpOverload\|aclrtLaunch\|host" $TORCHAIR/_acl_concrete_graph/acl_graph.py | head -60

# 3. npu_fx_compiler 的 run_kernel（决定哪些节点进图、哪些走 fallback）
sed -n '460,560p' $TORCHAIR/npu_fx_compiler.py


TORCHAIR=/usr/local/python3.12.13/lib/python3.12/site-packages/torch_npu/dynamo/npugraph_ex

# 1. run()/process_input() —— 看捕获和回放到底做了什么
sed -n '1010,1250p' $TORCHAIR/_acl_concrete_graph/acl_graph.py

# 2. warmup 次数默认值 & 有没有 op 排除/支持清单机制
grep -rn "num_warmup_iters" $TORCHAIR/ | head -10
grep -rn -i "unsupported\|exclude\|blacklist\|allowlist\|capturable\|partition" $TORCHAIR/_acl_concrete_graph/*.py $TORCHAIR/npu_fx_compiler.py | head -20
