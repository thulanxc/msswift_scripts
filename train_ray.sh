#!/bin/bash
# ==============================================================================
# Ray 多机训练启动脚本 - 在 Head 节点上执行
#
# 前提:
#   1. 所有节点已运行 start_ray.sh (head / worker)
#   2. 所有节点的数据路径一致
#   3. train_config.yaml 中的 dataset 路径已修改
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/train_config.yaml"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 未找到 ${CONFIG_FILE}"
    exit 1
fi

# 加载 NCCL 配置 (由 start_ray.sh 自动生成)
if [ -f "${SCRIPT_DIR}/.nccl_env" ]; then
    source "${SCRIPT_DIR}/.nccl_env"
    ok "已加载 NCCL 配置 (.nccl_env)"
else
    warn "未找到 .nccl_env, 请确认已运行 start_ray.sh"
    warn "将尝试自动探测网络接口..."
    NCCL_SOCKET_IFNAME=$(ip -br addr show \
        | grep ' UP ' \
        | grep -v -E '^(lo|docker|veth|br-|reth)' \
        | awk '$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' \
        | grep -E '^(eth|ens|eno)' | head -1)
    if [ -z "$NCCL_SOCKET_IFNAME" ]; then
        NCCL_SOCKET_IFNAME=$(ip -br addr show \
            | grep ' UP ' \
            | grep -v -E '^(lo|docker|veth|br-|reth)' \
            | awk '$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}' \
            | head -1)
    fi
    if [ -d /sys/class/infiniband ] && [ "$(ls /sys/class/infiniband 2>/dev/null)" ]; then
        NCCL_IB_DISABLE=0
    else
        NCCL_IB_DISABLE=1
    fi
    GLOO_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME}"
fi

export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME}"
export NCCL_IB_DISABLE="${NCCL_IB_DISABLE:-1}"
export NCCL_DEBUG="${NCCL_DEBUG:-INFO}"
export GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME:-$NCCL_SOCKET_IFNAME}"
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

# ===================== 构建 RAY_RUNTIME_ENV =====================
# Ray actor 是独立进程, shell 中 export 的变量不会自动传递。
# 通过 RAY_RUNTIME_ENV 注入环境变量到每个 Ray actor 中。

_RAY_ENV_VARS=""
_add_ray_env() {
    local key="$1" val="$2"
    if [ -n "$val" ]; then
        [ -n "$_RAY_ENV_VARS" ] && _RAY_ENV_VARS="${_RAY_ENV_VARS}, "
        _RAY_ENV_VARS="${_RAY_ENV_VARS}\"${key}\": \"${val}\""
    fi
}

_add_ray_env "NCCL_SOCKET_IFNAME"  "$NCCL_SOCKET_IFNAME"
_add_ray_env "NCCL_IB_DISABLE"     "$NCCL_IB_DISABLE"
_add_ray_env "NCCL_DEBUG"          "$NCCL_DEBUG"
_add_ray_env "GLOO_SOCKET_IFNAME"  "$GLOO_SOCKET_IFNAME"
_add_ray_env "PYTORCH_CUDA_ALLOC_CONF" "expandable_segments:True"

export RAY_RUNTIME_ENV="{\"env_vars\": {${_RAY_ENV_VARS}}}"

# 检查 Ray 集群状态
echo "============================================"
echo "  Ray 集群状态"
echo "============================================"
ray status
echo ""

echo "============================================"
echo "  NCCL 配置"
echo "============================================"
echo "  NCCL_SOCKET_IFNAME = ${NCCL_SOCKET_IFNAME:-<未设置>}"
echo "  NCCL_IB_DISABLE    = ${NCCL_IB_DISABLE}"
echo "  GLOO_SOCKET_IFNAME = ${GLOO_SOCKET_IFNAME:-<未设置>}"
echo "  NCCL_DEBUG         = ${NCCL_DEBUG}"
echo ""
echo "  RAY_RUNTIME_ENV 已配置 (环境变量将注入到每个 Ray actor)"
echo ""

echo "============================================"
echo "  启动训练"
echo "  配置: ${CONFIG_FILE}"
echo "============================================"
echo ""

swift sft --config "$CONFIG_FILE"
