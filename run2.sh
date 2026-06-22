#!/usr/bin/env bash
# 使用 msprof 采集 lightning_indexer_aicpu_bench 的 page mode 性能数据：
# elements=66536，fixed24 与 microbatch12，分别测试 poll=0 和 poll=1。
# 在 lightning_indexer_aicpu_bench/ 目录下执行。

set -euo pipefail

CANN_INSTALL_PATH="${CANN_INSTALL_PATH:-/usr/local/Ascend/cann-9.1.0}"
DEVICE="${DEVICE:-0}"
BS="${BS:-24}"
BUILD_DIR="${BUILD_DIR:-build}"
PROF_DIR="${PROF_DIR:-./prof}"
USE_MSPROF="${USE_MSPROF:-1}"

unset ASCEND_CUSTOM_OPP_PATH
unset PYTHONHOME
unset PYTHONPATH

source "${CANN_INSTALL_PATH}/set_env.sh" 2>/dev/null || source "${CANN_INSTALL_PATH}/bin/setenv.bash"
export PATH="/usr/local/bin:${PATH}"
hash -r

# Python 3.11 shim（CANN 9.1.0 在 910C 加载 custom op 需要）
PY311="${PY311:-$(command -v python3.11 || true)}"
[ -n "${PY311}" ] || { echo "ERROR: python3.11 not found" >&2; exit 1; }
PY311_CONFIG="${PY311_CONFIG:-$(command -v python3.11-config || true)}"
[ -x "${PY311_CONFIG}" ] || PY311_CONFIG="$(dirname "$(readlink -f "${PY311}")")/python3.11-config"
[ -x "${PY311_CONFIG}" ] || { echo "ERROR: python3.11-config not found" >&2; exit 1; }

PY_SHIM="/tmp/aicpu_py311_$$"
rm -rf "${PY_SHIM}" && mkdir -p "${PY_SHIM}"
ln -sf "${PY311}" "${PY_SHIM}/python3"
ln -sf "${PY311}" "${PY_SHIM}/python3.11"
printf '#!/usr/bin/env bash\nexec "%s" "$@"\n' "${PY311_CONFIG}" > "${PY_SHIM}/python3-config"
chmod +x "${PY_SHIM}/python3-config"
trap 'rm -rf "${PY_SHIM}"' EXIT

export PATH="${PY_SHIM}:${PATH}"
source "${CANN_INSTALL_PATH}/set_env.sh" 2>/dev/null || source "${CANN_INSTALL_PATH}/bin/setenv.bash"
export PATH="${PY_SHIM}:${PATH}"
hash -r

cd "$(dirname "${BASH_SOURCE[0]}")"

rm -rf "${BUILD_DIR}" && mkdir "${BUILD_DIR}" && cd "${BUILD_DIR}"
cmake .. -DCANN_INSTALL_PATH="${CANN_INSTALL_PATH}" -DNPU_ARCH=dav-c220 -DASC_ARCH_FLAG=--cce-aicore-arch -DENABLE_EXTRA_ASC_FLAGS=OFF
make -j

export ASCEND_CUSTOM_OPP_PATH="${PWD}/custom_opp/vendors/cust"
export LD_LIBRARY_PATH="${ASCEND_CUSTOM_OPP_PATH}/op_proto/lib/linux/$(uname -m):${ASCEND_CUSTOM_OPP_PATH}/op_impl/cpu/aicpu_kernel/impl:${LD_LIBRARY_PATH:-}"

# msprof 采集开关：
# - sys-profiling:        CPU 利用率、系统级时间线
# - sys-hardware-mem:     片上内存 / LLC / HBM 带宽与内存占用
# - sys-pid-profiling:    进程级 CPU / 内存采样
# - ai-core:              AI Core 算子耗时与硬件计数器
# - aicpu:                AICPU kernel 耗时
# - runtime-api:          ACL Runtime API 调用耗时
# - task-time:            任务下发与执行耗时
# - instr-profiling:      AI Core / AI Vector 带宽与延时（A2/A3 单算子场景）
MSPROF_COMMON_OPTS=(
  --sys-profiling=on
  --sys-hardware-mem=on
  --sys-hardware-mem-freq=10
  --sys-pid-profiling=on
  --sys-pid-sampling-freq=10
  --ai-core=on
  --aicpu=on
  --runtime-api=on
  --task-time=on
  --instr-profiling=on
  --instr-profiling-freq=1000
)

run() {
  local tiling=$1
  local core_or_mb=$2
  local poll=$3
  local extra_args=""
  local case_name="${tiling}${core_or_mb}_poll${poll}"
  local prof_out="${PROF_DIR}/${case_name}"

  if [ "${tiling}" = "fixed" ]; then
    extra_args="--used-core-num=${core_or_mb}"
  elif [ "${tiling}" = "microbatch" ]; then
    extra_args="--microbatch-size=${core_or_mb}"
  fi

  rm -rf "${prof_out}"
  mkdir -p "${prof_out}"

  local app="./lightning_indexer_aicpu_bench --device=${DEVICE} --bs=${BS} --elements=66536 --page=1 --var-len=0 --tiling=${tiling} ${extra_args} --poll=${poll} --warmup=1 --iters=1 --timeout-ms=30000 --check=1 --detail=1"

  echo "---- ${case_name}: bs=${BS} elements=66536 ----"
  if [ "${USE_MSPROF}" = "1" ]; then
    msprof --application="${app}" --output="${prof_out}" "${MSPROF_COMMON_OPTS[@]}"
  else
    # shellcheck disable=SC2086
    ${app}
  fi
  echo "ret=$?"
}

run fixed 24 0
run fixed 24 1
run microbatch 12 0
run microbatch 12 1

echo "All profiling data saved under: ${PWD}/${PROF_DIR}"
