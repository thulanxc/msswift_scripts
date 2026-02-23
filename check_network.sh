#!/bin/bash
# ==============================================================================
# 网络探测脚本 - 在每台机器上执行，收集多机训练所需的网络信息
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "============================================"
echo "  机器网络信息探测"
echo "============================================"
echo ""

# ---------- 1. 主机名 ----------
echo "[1] 主机名:"
hostname
echo ""

# ---------- 2. IP 地址 ----------
echo "[2] 所有 IP 地址:"
hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}'
echo ""

# ---------- 3. 网络接口详情 ----------
echo "[3] 网络接口列表 (用于确定 NCCL_SOCKET_IFNAME):"
echo ""
echo -e "    ${GREEN}可用接口 (有 IP, 适合做 NCCL_SOCKET_IFNAME):${NC}"
echo "    ---"
ip -br addr show | grep ' UP ' | grep -v '^lo ' | while read -r line; do
    ifname=$(echo "$line" | awk '{print $1}')
    addr=$(echo "$line" | awk '{print $3}')
    if echo "$addr" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo -e "    ${GREEN}●${NC} $line"
    fi
done
echo ""
echo -e "    ${YELLOW}其他 UP 接口 (无 IP, 不能直接用):${NC}"
echo "    ---"
ip -br addr show | grep ' UP ' | grep -v '^lo ' | while read -r line; do
    addr=$(echo "$line" | awk '{print $3}')
    if ! echo "$addr" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
        echo -e "    ${YELLOW}○${NC} $line"
    fi
done
echo ""

# ---------- 4. 自动推荐接口 ----------
echo "[4] 推荐 NCCL_SOCKET_IFNAME:"
RECOMMENDED=$(ip -br addr show \
    | grep ' UP ' \
    | grep -v -E '^(lo|docker|veth|br-|reth)' \
    | awk '$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/ {print $1}')
ETH_IF=$(echo "$RECOMMENDED" | grep -E '^(eth|ens|eno)' | head -1)
FIRST_IF=$(echo "$RECOMMENDED" | head -1)
if [ -n "$ETH_IF" ]; then
    PICK="$ETH_IF"
elif [ -n "$FIRST_IF" ]; then
    PICK="$FIRST_IF"
else
    PICK=""
fi

if [ -n "$PICK" ]; then
    PICK_ADDR=$(ip -br addr show dev "$PICK" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
    echo -e "    推荐: ${GREEN}${PICK}${NC} (${PICK_ADDR})"
    echo ""
    echo "    所有候选 (有 IP 且非底层/虚拟接口):"
    for iface in $RECOMMENDED; do
        iface_addr=$(ip -br addr show dev "$iface" 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
        if [ "$iface" = "$PICK" ]; then
            echo -e "      ${GREEN}→ ${iface}${NC} (${iface_addr}) ← 推荐"
        else
            echo "        ${iface} (${iface_addr})"
        fi
    done
else
    echo -e "    ${RED}无法自动推荐, 请手动选择一个有 IP 的接口${NC}"
fi
echo ""

# ---------- 5. InfiniBand / RoCE 状态 ----------
echo "[5] InfiniBand / RoCE 状态 (用于确定 NCCL_IB_DISABLE):"
if command -v ibstat &>/dev/null; then
    echo "    ibstat 可用, 有 InfiniBand/RoCE 硬件 → 建议 NCCL_IB_DISABLE=0"
    ibstat | head -20
elif command -v ibstatus &>/dev/null; then
    echo "    ibstatus 可用, 有 InfiniBand/RoCE 硬件 → 建议 NCCL_IB_DISABLE=0"
    ibstatus | head -20
else
    echo "    未检测到 ibstat/ibstatus 命令"
    echo "    再检查 /sys/class/infiniband/ ..."
    if [ -d /sys/class/infiniband ] && [ "$(ls /sys/class/infiniband 2>/dev/null)" ]; then
        echo -e "    发现 IB 设备: ${GREEN}$(ls /sys/class/infiniband | tr '\n' ' ')${NC}"
        echo "    → 建议 NCCL_IB_DISABLE=0"
    else
        echo "    未发现 InfiniBand 设备 → 建议 NCCL_IB_DISABLE=1 (走 TCP)"
    fi
fi
echo ""

# ---------- 6. GPU 信息 ----------
echo "[6] GPU 信息:"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
else
    echo "    nvidia-smi 不可用"
fi
echo ""

# ---------- 7. 端口可用性检测 ----------
DEFAULT_PORT=29500
echo "[7] 默认通信端口 ${DEFAULT_PORT} 是否被占用:"
if command -v ss &>/dev/null; then
    if ss -tlnp | grep -q ":${DEFAULT_PORT} "; then
        echo "    端口 ${DEFAULT_PORT} 已被占用! 请换一个端口"
        echo "    占用进程: $(ss -tlnp | grep ":${DEFAULT_PORT} ")"
    else
        echo "    端口 ${DEFAULT_PORT} 空闲, 可以使用"
    fi
elif command -v netstat &>/dev/null; then
    if netstat -tlnp 2>/dev/null | grep -q ":${DEFAULT_PORT} "; then
        echo "    端口 ${DEFAULT_PORT} 已被占用!"
    else
        echo "    端口 ${DEFAULT_PORT} 空闲, 可以使用"
    fi
else
    echo "    无法检测 (ss/netstat 不可用), 请手动确认"
fi
echo ""

# ---------- 8. 节点间连通性测试 ----------
echo "[8] 节点间连通性测试:"
echo "    请手动在本机执行以下命令, 测试与其他节点的连通:"
echo ""
echo '    # 把 <OTHER_NODE_IP> 换成其他节点的 IP'
echo '    ping -c 3 <OTHER_NODE_IP>'
echo '    ssh <OTHER_NODE_IP> "hostname && nvidia-smi -L"'
echo ""

# ---------- 9. 当前 NCCL 环境变量 ----------
echo "[9] 当前 NCCL 相关环境变量:"
env | grep -E '^(NCCL_|GLOO_|MASTER_|TORCH_|RAY_RUNTIME_ENV)' 2>/dev/null | sort || echo "    无"
echo ""

# ---------- 汇总 ----------
echo "============================================"
echo "  汇总: 你需要在训练脚本中填写的信息"
echo "============================================"
echo ""
echo "  MASTER_ADDR    = <node0 的 IP, 从上面 [2] 中选取节点间互通的那个>"
echo "  MASTER_PORT    = 29500 (如果 [7] 显示被占用则换一个)"
echo "  NCCL_SOCKET_IFNAME = ${PICK:-<从 [3] 中选取>}  (从 [4] 推荐)"
if [ -d /sys/class/infiniband ] && [ "$(ls /sys/class/infiniband 2>/dev/null)" ]; then
    echo "  NCCL_IB_DISABLE    = 0  (检测到 IB 设备)"
else
    echo "  NCCL_IB_DISABLE    = 1  (未检测到 IB 设备)"
fi
echo ""
echo "  具体怎么确定接口名:"
echo "    1. 看 [3] 的输出中绿色标记的接口 (有 IP 的)"
echo "    2. 选那个 IP 地址跟其他节点在同一网段的接口"
echo "    3. 用 ping 验证: 在 node1 上 ping node0 的那个 IP 能通, 就是对的"
echo "    4. 如果有 IB 接口 (ib0), 优先用 IB; 否则用以太网接口"
echo ""
echo "  Ray 方案提示:"
echo "    start_ray.sh 会自动探测并保存到 .nccl_env"
echo "    train_ray.sh 会自动读取并通过 RAY_RUNTIME_ENV 注入到 Ray actor"
echo "    如需手动覆盖, 编辑 .nccl_env 后重新运行 train_ray.sh 即可"
echo ""
