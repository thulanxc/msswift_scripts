#!/bin/bash
# ==============================================================================
# Ray 集群启动脚本 - 在每台机器上执行
#
# 用法:
#   Head 节点:    bash start_ray.sh head
#   Worker 节点:  bash start_ray.sh worker <HEAD_IP>
#
# 启动前会自动探测 NCCL 网络配置
# ==============================================================================
set -e

MODE=${1:?"用法: bash start_ray.sh head  或  bash start_ray.sh worker <HEAD_IP>"}

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()   { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }

RAY_PORT=6379
DASHBOARD_PORT=8265

# ===================== 停掉已有 Ray =====================

if ray status &>/dev/null; then
    warn "检测到已运行的 Ray 实例, 先停止..."
    ray stop --force 2>/dev/null || true
    sleep 2
fi

# ===================== NCCL 自动探测 =====================

info "探测 NCCL 网络配置..."

# IB 检测
if [ -d /sys/class/infiniband ] && [ "$(ls /sys/class/infiniband 2>/dev/null)" ]; then
    export NCCL_IB_DISABLE=0
    IB_DEVS=$(ls /sys/class/infiniband 2>/dev/null | tr '\n' ' ')
    ok "发现 InfiniBand/RoCE 设备: ${IB_DEVS}→ NCCL_IB_DISABLE=0"
else
    export NCCL_IB_DISABLE=1
    info "未发现 InfiniBand → NCCL_IB_DISABLE=1 (走 TCP)"
fi

# 接口名探测:
#   1. 排除 lo/docker/veth/br-/reth (reth 是 bond 的底层口, 通常无 IP)
#   2. 只保留有 IPv4 地址的接口 (第三列包含 x.x.x.x/)
#   3. 优先选 eth/ens/eno 等常规以太网接口
IFNAME=""
_pick_iface() {
    ip -br addr show \
        | grep ' UP ' \
        | grep -v -E '^(lo|docker|veth|br-|reth)' \
        | awk '$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}'
}

_CANDIDATES=$(_pick_iface)
if [ -n "$_CANDIDATES" ]; then
    # 优先选 eth*/ens*/eno* 等常规接口
    IFNAME=$(echo "$_CANDIDATES" | grep -E '^(eth|ens|eno)' | head -1)
    # 如果没有常规接口, 取第一个有 IP 的
    [ -z "$IFNAME" ] && IFNAME=$(echo "$_CANDIDATES" | head -1)
fi

if [ -n "$IFNAME" ]; then
    export NCCL_SOCKET_IFNAME="$IFNAME"
    export GLOO_SOCKET_IFNAME="$IFNAME"
    _IFADDR=$(ip -br addr show dev "$IFNAME" | awk '{print $3}' | cut -d/ -f1)
    ok "网络接口: ${IFNAME} (${_IFADDR})"
else
    warn "无法自动检测网络接口, NCCL 将自动选择"
    warn "如果训练报错, 请手动设置: export NCCL_SOCKET_IFNAME=<接口名>"
    info "当前接口列表:"
    ip -br addr show | grep ' UP ' | grep -v '^lo '
fi

export NCCL_DEBUG=${NCCL_DEBUG:-INFO}

# ===================== 启动 Ray =====================

NUM_GPUS=$(nvidia-smi -L 2>/dev/null | wc -l)
info "本机 GPU 数: ${NUM_GPUS}"

if [ "$MODE" = "head" ]; then
    info "启动 Ray Head 节点..."
    RAY_memory_monitor_refresh_ms=0 ray start --head \
        --port=${RAY_PORT} \
        --dashboard-host=0.0.0.0 \
        --dashboard-port=${DASHBOARD_PORT} \
        --num-gpus=${NUM_GPUS}

    HEAD_IP=$(hostname -I | awk '{print $1}')
    echo ""
    ok "Ray Head 已启动!"
    echo ""
    echo "  Dashboard: http://${HEAD_IP}:${DASHBOARD_PORT}"
    echo ""
    echo "  在每台 worker 机器上执行:"
    echo "    bash start_ray.sh worker ${HEAD_IP}"
    echo ""
    echo "  所有 worker 加入后, 执行:"
    echo "    bash train_ray.sh"
    echo ""

elif [ "$MODE" = "worker" ]; then
    HEAD_IP=${2:?"Worker 模式需要指定 HEAD_IP: bash start_ray.sh worker <HEAD_IP>"}
    info "加入 Ray 集群 (Head: ${HEAD_IP}:${RAY_PORT})..."
    RAY_memory_monitor_refresh_ms=0 ray start \
        --address="${HEAD_IP}:${RAY_PORT}" \
        --num-gpus=${NUM_GPUS}

    echo ""
    ok "已加入 Ray 集群!"
    echo ""

else
    echo "错误: 未知模式 '${MODE}'"
    echo "用法: bash start_ray.sh head  或  bash start_ray.sh worker <HEAD_IP>"
    exit 1
fi

# 保存 NCCL 配置供训练脚本使用
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cat > "${SCRIPT_DIR}/.nccl_env" << EOF
export NCCL_SOCKET_IFNAME="${NCCL_SOCKET_IFNAME}"
export NCCL_IB_DISABLE=${NCCL_IB_DISABLE}
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export GLOO_SOCKET_IFNAME="${GLOO_SOCKET_IFNAME}"
EOF
ok "NCCL 配置已保存到 .nccl_env"

echo ""
info "当前 NCCL 配置:"
echo "  NCCL_SOCKET_IFNAME = ${NCCL_SOCKET_IFNAME:-<未设置>}"
echo "  NCCL_IB_DISABLE    = ${NCCL_IB_DISABLE}"
echo "  GLOO_SOCKET_IFNAME = ${GLOO_SOCKET_IFNAME:-<未设置>}"
echo "  NCCL_DEBUG         = ${NCCL_DEBUG:-INFO}"
