# REDSearcher SFT 训练 (多机版)

Qwen3-4B-Thinking-2507 全参数 SFT，支持单机 8 卡和多机 (6×8=48 GPU) 训练。

## 文件说明

### 数据准备

| 文件 | 说明 |
|------|------|
| `download_data.py` | 从 HuggingFace 下载 REDSearcher_SFT_10K 原始数据集 |
| `filter_data.py` | 数据过滤脚本。从原始数据中筛选出仅使用指定工具 (默认 search + visit) 的样本，清理 tool_call JSON，输出到 `data_filtered/` |

### 单机训练 (8 GPU)

| 文件 | 说明 |
|------|------|
| `train_sft.sh` | 单机 8 卡训练脚本。需修改 `DATA_PATH` 和 `MODEL_PATH` |
| `training_guide.html` | 单机训练的详细教程 (浏览器打开) |

### 多机训练 (6×8=48 GPU)

| 文件 | 说明 |
|------|------|
| `nodes.conf` | **唯一需要手动编辑的文件**。填入 6 台机器的 IP、SSH 用户名、数据/模型路径 |
| `configure.sh` | 自动配置脚本。读取 `nodes.conf`，探测网络接口、IB 状态、端口，配置免密 SSH，生成 `env.sh` |
| `env.sh` | 由 `configure.sh` 自动生成的完整集群配置，所有脚本从此文件读取参数 (不要手动编辑) |
| `setup_env.sh` | 环境安装脚本。安装 ms-swift 和 DeepSpeed (每台机器执行一次) |
| `check_network.sh` | 网络诊断工具。输出 IP、接口名、IB 状态等信息，用于手动排查网络问题 |
| `sync_data.sh` | 数据同步脚本。从 node0 将数据、脚本、配置 rsync 到所有 worker 节点，并远程安装环境 |
| `launch_all.sh` | 一键启动脚本。从 node0 通过 SSH 启动所有节点训练，node0 在前台运行 |
| `train_multinode.sh` | 核心多机训练脚本。接受 `NODE_RANK` 参数 (0-5)，由 `launch_all.sh` 自动调用 |
| `multinode_training_guide.html` | 多机训练的详细教程 (浏览器打开) |

### 其他

| 文件/目录 | 说明 |
|-----------|------|
| `ms-swift/` | ms-swift 框架源码 (git clone)，仅供参考，实际使用 pip 安装的版本 |

## 多机训练快速上手

```bash
vim nodes.conf          # 填 6 个 IP + 数据路径
bash configure.sh       # 自动探测网络、配置 SSH、生成 env.sh
bash setup_env.sh       # 本机安装 ms-swift
bash sync_data.sh       # 同步到所有节点
bash launch_all.sh      # 一键启动 48 GPU 训练
```

详见 `multinode_training_guide.html`。
