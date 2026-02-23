# REDSearcher SFT 训练

Qwen3-4B-Thinking-2507 全参数 SFT，支持单机 8 卡和多机分布式训练。

多机提供两种方案：**Ray 方案**（无需节点间 SSH）和 **SSH 方案**（传统方式），按需选择。

## 文件说明

### 数据准备

| 文件 | 说明 |
|------|------|
| `download_data.py` | 从 HuggingFace 下载 REDSearcher_SFT_10K 原始数据集 |
| `filter_data.py` | 数据过滤脚本。筛选出仅使用指定工具的样本，输出到 `data_filtered/` |

### 单机训练 (8 GPU)

| 文件 | 说明 |
|------|------|
| `train_sft.sh` | 单机 8 卡训练脚本。需修改 `DATA_PATH` 和 `MODEL_PATH` |
| `training_guide.html` | 单机训练的详细教程 (浏览器打开) |

### 多机训练 — Ray 方案 (推荐，无需节点间 SSH)

| 文件 | 说明 |
|------|------|
| `setup_env.sh` | 环境安装。安装 ms-swift、DeepSpeed、Ray (每台机器执行) |
| `start_ray.sh` | 启动 Ray 集群。head 模式或 worker 模式，自动探测 NCCL 网络配置 |
| `train_config.yaml` | 训练参数配置。需修改 `dataset` 路径 |
| `train_ray.sh` | 在 head 节点提交训练任务 |
| `stop_ray.sh` | 停止 Ray (每台机器执行) |

### 多机训练 — SSH 方案 (需节点间免密 SSH)

| 文件 | 说明 |
|------|------|
| `nodes.conf` | 集群配置。填入节点 IP (有几台写几行)、SSH 用户名、数据/模型路径 |
| `configure.sh` | 自动配置脚本。探测网络、配置 SSH、生成 `env.sh` |
| `env.sh` | 由 `configure.sh` 自动生成，所有 SSH 方案脚本从此读取参数 |
| `sync_data.sh` | 从 node0 将数据、脚本同步到所有节点 |
| `launch_all.sh` | 一键启动所有节点训练 |
| `train_multinode.sh` | 核心训练脚本，接受 `NODE_RANK` 参数 |

### 通用 / 诊断

| 文件 | 说明 |
|------|------|
| `check_network.sh` | 网络诊断工具。输出 IP、接口名、IB 状态，用于排查 |
| `multinode_training_guide.html` | 多机训练详细教程 (浏览器打开) |
| `ms-swift/` | ms-swift 框架源码 (仅供参考) |

---

## Ray 方案快速上手

```bash
# ---- 在每台机器上分别执行 ----
bash setup_env.sh                          # 安装环境
python download_data.py                    # 下载数据
python filter_data.py                      # 过滤数据

# ---- 在 head 节点 (选一台) ----
bash start_ray.sh head                     # 启动 Ray head

# ---- 在每台 worker 节点 ----
bash start_ray.sh worker <HEAD_IP>         # 加入集群

# ---- 在 head 节点 ----
vim train_config.yaml                      # 修改 dataset 路径
bash train_ray.sh                          # 启动训练
```

## SSH 方案快速上手

```bash
vim nodes.conf          # 填节点 IP + 数据路径
bash configure.sh       # 自动探测网络、配置 SSH、生成 env.sh
bash setup_env.sh       # 本机安装环境
bash sync_data.sh       # 同步到所有节点
bash launch_all.sh      # 一键启动训练
```
