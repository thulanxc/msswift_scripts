#!/bin/bash
# ==============================================================================
# 数据 & 环境同步脚本 - 在主节点 (node0) 上执行
# 将脚本、配置、数据同步到所有 worker 节点, 并远程安装环境
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.sh"

if [ ! -f "$ENV_FILE" ]; then
    echo "错误: 未找到 ${ENV_FILE}, 请先运行 bash configure.sh"
    exit 1
fi

source "$ENV_FILE"

echo ""
echo "============================================"
echo "  数据 & 环境同步 (node1 ~ node$((NNODES-1)))"
echo "============================================"

for i in $(seq 1 $((NNODES - 1))); do
    ip=${CLUSTER_NODES[$i]}
    echo ""
    echo ">>> [node${i}] ${ip}"

    echo "    [1/3] 同步脚本和配置..."
    ssh "${SSH_USER}@${ip}" "mkdir -p ${SCRIPT_DIR}"
    rsync -avz --progress \
        "${SCRIPT_DIR}/setup_env.sh" \
        "${SCRIPT_DIR}/train_multinode.sh" \
        "${SCRIPT_DIR}/env.sh" \
        "${SSH_USER}@${ip}:${SCRIPT_DIR}/"

    echo "    [2/3] 同步数据 (可能需要较长时间)..."
    ssh "${SSH_USER}@${ip}" "mkdir -p ${DATA_PATH}"
    rsync -avz --progress \
        "${DATA_PATH}/" \
        "${SSH_USER}@${ip}:${DATA_PATH}/"

    echo "    [3/3] 远程安装 ms-swift & deepspeed..."
    ssh "${SSH_USER}@${ip}" "cd ${SCRIPT_DIR} && bash setup_env.sh"

    echo "    [node${i}] 完成!"
done

echo ""
echo "============================================"
echo "  全部同步完成! (${NNODES} 节点)"
echo "  下一步: bash launch_all.sh"
echo "============================================"
