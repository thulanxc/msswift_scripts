#!/bin/bash
# ==============================================================================
# 环境安装脚本 - 在每台机器上执行
# 前提: 机器已有 Python、PyTorch (CUDA)、flash-attn
# ==============================================================================
set -e

pip install ms-swift -U
pip install deepspeed -U

python -c "
import torch, swift, deepspeed
print(f'PyTorch:    {torch.__version__}')
print(f'CUDA avail: {torch.cuda.is_available()}, GPUs: {torch.cuda.device_count()}')
print(f'ms-swift:   {swift.__version__}')
print(f'DeepSpeed:  {deepspeed.__version__}')
print('All OK!')
"
