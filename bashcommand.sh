TORCHAIR=/usr/local/python3.12.13/lib/python3.12/site-packages/torch_npu/dynamo/npugraph_ex

# 1. acl_graph 的 __call__ 和 compile 全貌（录制/回放的核心逻辑）
sed -n '780,1000p' $TORCHAIR/_acl_concrete_graph/acl_graph.py

# 2. 它如何处理图里的自定义 op（fallback/eager/custom 关键字）
grep -n -i "fallback\|custom\|eager\|call_function\|OpOverload\|aclrtLaunch\|host" $TORCHAIR/_acl_concrete_graph/acl_graph.py | head -60

# 3. npu_fx_compiler 的 run_kernel（决定哪些节点进图、哪些走 fallback）
sed -n '460,560p' $TORCHAIR/npu_fx_compiler.py
