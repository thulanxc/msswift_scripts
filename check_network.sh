#!/bin/bash
# ==============================================================================
# 网络探测脚本 - 在每台机器上执行，收集多机训练所需的网络信息
# ==============================================================================

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
echo "    需要找到节点间互通的那个接口名 (第一列)"
echo "    ---"
ip -br addr show | grep -v "^lo "
echo ""

# ---------- 4. InfiniBand / RoCE 状态 ----------
echo "[4] InfiniBand / RoCE 状态 (用于确定 NCCL_IB_DISABLE):"
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
        echo "    发现 IB 设备: $(ls /sys/class/infiniband)"
        echo "    → 建议 NCCL_IB_DISABLE=0"
    else
        echo "    未发现 InfiniBand 设备 → 建议 NCCL_IB_DISABLE=1 (走 TCP)"
    fi
fi
echo ""

# ---------- 5. GPU 信息 ----------
echo "[5] GPU 信息:"
if command -v nvidia-smi &>/dev/null; then
    nvidia-smi --query-gpu=index,name,memory.total --format=csv,noheader
else
    echo "    nvidia-smi 不可用"
fi
echo ""

# ---------- 6. 端口可用性检测 ----------
DEFAULT_PORT=29500
echo "[6] 默认通信端口 ${DEFAULT_PORT} 是否被占用:"
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

# ---------- 7. 节点间连通性测试 ----------
echo "[7] 节点间连通性测试:"
echo "    请手动在本机执行以下命令, 测试与其他节点的连通:"
echo ""
echo '    # 把 <OTHER_NODE_IP> 换成其他节点的 IP'
echo '    ping -c 3 <OTHER_NODE_IP>'
echo '    ssh <OTHER_NODE_IP> "hostname && nvidia-smi -L"'
echo ""

# ---------- 汇总 ----------
echo "============================================"
echo "  汇总: 你需要在训练脚本中填写的信息"
echo "============================================"
echo ""
echo "  MASTER_ADDR    = <node0 的 IP, 从上面 [2] 中选取节点间互通的那个>"
echo "  MASTER_PORT    = 29500 (如果 [6] 显示被占用则换一个)"
echo "  NCCL_SOCKET_IFNAME = <从 [3] 中选取节点间互通的接口名>"
echo "  NCCL_IB_DISABLE    = <参考 [4] 的建议>"
echo ""
echo "  具体怎么确定接口名:"
echo "    1. 看 [3] 的输出, 比如 eth0/bond0/ens5f0/ib0 等"
echo "    2. 选那个 IP 地址跟其他节点在同一网段的接口"
echo "    3. 用 ping 验证: 在 node1 上 ping node0 的那个 IP 能通, 就是对的"
echo "    4. 如果有 IB 接口 (ib0), 优先用 IB; 否则用以太网接口"
echo ""
