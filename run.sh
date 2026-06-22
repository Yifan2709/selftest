#!/usr/bin/env bash
# 运行 lightning_indexer_aicpu_bench/COMMAND.md #2026-06-22 16:27:48 的 page microbatch 回归用例。
# 在 lightning_indexer_aicpu_bench/ 目录下执行。

set -euo pipefail

CANN_INSTALL_PATH="${CANN_INSTALL_PATH:-/usr/local/Ascend/cann-9.1.0}"
DEVICE="${DEVICE:-0}"
BUILD_DIR="${BUILD_DIR:-build}"

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

run() {
  echo "---- bs=$1 elements=$2 warmup=$3 ----"
  ./lightning_indexer_aicpu_bench --device="${DEVICE}" --bs="$1" --elements="$2" --page=1 --var-len=0 \
    --tiling=microbatch --microbatch-size=12 --warmup="$3" --iters=1 --timeout-ms=30000 --check=1 --detail=1
  echo "ret=$?"
}

run 13 2048 1
run 13 8192 1
run 13  512 0
run 24 2048 1
