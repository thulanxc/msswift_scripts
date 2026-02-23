#!/bin/bash
# ==============================================================================
# Qwen3-4B-Thinking-2507 Full-Parameter SFT on 8x H200
# ==============================================================================
#
# Global batch size = per_device(1) × num_gpus(8) × grad_accum(16) = 128
# LR: 5e-5 → 1e-6, cosine decay
# Max sequence length: 128K (131072)
# Model native max_position_embeddings: 262144 (256K), 无需 rope_scaling
#
# 数据概况: ~8937 条, 每条 28~322 轮对话 (平均 128 轮)
# 预计每 epoch ~70 steps, 3 epochs ~210 steps
# ==============================================================================

# ---- 修改以下路径 ----
MODEL_PATH="Qwen/Qwen3-4B-Thinking-2507"   # 或本地已下载的模型路径
DATA_PATH="/path/to/data_filtered"           # 修改为实际的 parquet 数据文件夹路径
OUTPUT_DIR="./output/qwen3-4b-thinking-sft"

export PYTORCH_CUDA_ALLOC_CONF=expandable_segments:True

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
    --gradient_accumulation_steps 16 \
    --learning_rate 5e-5 \
    --lr_scheduler_type cosine_with_min_lr \
    --lr_scheduler_kwargs '{"min_lr": 1e-6}' \
    --warmup_ratio 0.03 \
    --weight_decay 0.01 \
    --gradient_checkpointing true \
    --attn_impl flash_attn \
    --deepspeed zero3 \
    --save_strategy steps \
    --save_steps 50 \
    --save_total_limit 5 \
    --logging_steps 1 \
    --output_dir ${OUTPUT_DIR} \
    --dataloader_num_workers 8 \
    --dataset_num_proc 8 \
    --use_hf true
