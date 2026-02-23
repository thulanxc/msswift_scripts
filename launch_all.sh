#!/bin/bash
# ==============================================================================
# 一键启动脚本 - 在主节点 (node0) 上执行
# 通过 SSH 启动所有节点的训练, node0 在前台运行
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.sh"

if [ ! -f "$ENV_FILE" ]; then
    echo "错误: 未找到 ${ENV_FILE}, 请先运行 bash configure.sh"
    exit 1
fi

source "$ENV_FILE"

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"

echo ""
echo "============================================"
echo "  启动 ${NNODES} 节点 × ${NPROC_PER_NODE} GPU 分布式训练"
echo "  总 GPU 数: ${TOTAL_GPUS}"
echo "  日志: ${LOG_DIR}/node{0..$((NNODES-1))}.log"
echo "============================================"
echo ""

# 先启动 node1 ~ node(N-1) (后台)
for i in $(seq 1 $((NNODES - 1))); do
    ip=${CLUSTER_NODES[$i]}
    echo "[启动] node${i} (${ip})"
    ssh "${SSH_USER}@${ip}" \
        "mkdir -p ${SCRIPT_DIR}/logs && cd ${SCRIPT_DIR} && nohup bash train_multinode.sh ${i} > logs/node${i}.log 2>&1 &"
done

echo ""
echo "[启动] node0 (本机, 前台运行)"
echo "--------------------------------------------"
echo ""

bash "${SCRIPT_DIR}/train_multinode.sh" 0 2>&1 | tee "${LOG_DIR}/node0.log"
