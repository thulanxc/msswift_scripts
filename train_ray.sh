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

if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误: 未找到 ${CONFIG_FILE}"
    exit 1
fi

# 加载 NCCL 配置 (由 start_ray.sh 自动生成)
if [ -f "${SCRIPT_DIR}/.nccl_env" ]; then
    source "${SCRIPT_DIR}/.nccl_env"
fi

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}

# H200 + NCCL 2.27+ 常见兼容性修复
# 如果 NCCL 报 ncclInvalidUsage, 取消下方注释逐个尝试:
# export NCCL_P2P_DISABLE=1
# export NCCL_SHM_DISABLE=1
# export TORCH_NCCL_USE_COMM_NONBLOCKING=0

# 检查 Ray 集群状态
echo "============================================"
echo "  Ray 集群状态"
echo "============================================"
ray status
echo ""

echo "============================================"
echo "  启动训练"
echo "  配置: ${CONFIG_FILE}"
echo "============================================"
echo ""

swift sft --config "$CONFIG_FILE"
