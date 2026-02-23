#!/bin/bash
# ==============================================================================
# Qwen3-4B-Thinking-2507 多机全参数 SFT
# 6 台机器 × 8 卡 H200 = 48 GPU
# Global batch size = 1 × 48 × 4 = 192
# ==============================================================================
#
# 用法:  bash train_multinode.sh <NODE_RANK>
#   NODE_RANK: 0-5, 对应 6 台机器
#
# 前提: 已运行 configure.sh 生成 env.sh
# ==============================================================================
set -e

NODE_RANK=${1:?"用法: bash train_multinode.sh <NODE_RANK>  (0-5)"}

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/env.sh"

if [ ! -f "$ENV_FILE" ]; then
    echo "错误: 未找到 ${ENV_FILE}, 请先运行 bash configure.sh"
    exit 1
fi

source "$ENV_FILE"

export NCCL_SOCKET_IFNAME
export NCCL_IB_DISABLE
export NCCL_DEBUG=${NCCL_DEBUG:-INFO}
export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

NNODES=6 \
NODE_RANK=$NODE_RANK \
MASTER_ADDR=$MASTER_ADDR \
MASTER_PORT=$MASTER_PORT \
NPROC_PER_NODE=8 \
CUDA_VISIBLE_DEVICES=0,1,2,3,4,5,6,7 \
swift sft \
    --model ${MODEL_PATH} \
    --dataset ${DATA_PATH} \
    --train_type full \
    --torch_dtype bfloat16 \
    --bf16 true \
    --max_length 131072 \
    --num_train_epochs 3 \
    --per_device_train_batch_size 1 \
    --per_device_eval_batch_size 1 \
    --gradient_accumulation_steps 4 \
    --learning_rate 5e-5 \
    --lr_scheduler_type cosine_with_min_lr \
    --lr_scheduler_kwargs '{"min_lr": 1e-6}' \
    --warmup_ratio 0.03 \
    --weight_decay 0.01 \
    --gradient_checkpointing true \
    --attn_impl flash_attn \
    --deepspeed zero2 \
    --save_strategy steps \
    --save_steps 50 \
    --save_total_limit 5 \
    --logging_steps 1 \
    --output_dir ${OUTPUT_DIR} \
    --dataloader_num_workers 8 \
    --dataset_num_proc 8 \
    --use_hf true
