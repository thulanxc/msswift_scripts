#!/bin/bash
# ==============================================================================
# 自动配置脚本 - 在主节点 (node0) 上执行
# 读取 nodes.conf → 探测网络 → 配置 SSH → 生成 env.sh
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONF_FILE="${SCRIPT_DIR}/nodes.conf"
ENV_FILE="${SCRIPT_DIR}/env.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC} $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail()  { echo -e "${RED}[FAIL]${NC} $*"; }

# ===================== 读取配置 =====================

if [ ! -f "$CONF_FILE" ]; then
    fail "未找到 ${CONF_FILE}"
    echo "请先编辑 nodes.conf, 填入机器 IP 和数据路径"
    exit 1
fi

source "$CONF_FILE"

NNODES=${#NODES[@]}

echo ""
echo "============================================"
echo "  多机训练自动配置 (${NNODES} 节点)"
echo "============================================"
echo ""

# ---- 校验 ----
if [ "$NNODES" -lt 1 ]; then
    fail "NODES 数组为空, 请在 nodes.conf 中填入至少 1 个节点 IP"
    exit 1
fi

VALIDATION_OK=true

for i in "${!NODES[@]}"; do
    ip="${NODES[$i]}"
    if [[ -z "$ip" || "$ip" == *"xxx"* ]]; then
        fail "NODES[$i] 未正确配置 (当前值: ${ip})"
        VALIDATION_OK=false
    fi
done

for var in SSH_USER DATA_PATH MODEL_PATH; do
    val="${!var}"
    if [[ -z "$val" || "$val" == "/path/to"* ]]; then
        fail "${var} 未正确配置 (当前值: ${val})"
        VALIDATION_OK=false
    fi
done

if [ "$VALIDATION_OK" != "true" ]; then
    echo ""
    fail "请编辑 nodes.conf 填写正确的值后重试"
    exit 1
fi

ok "nodes.conf 验证通过"
echo "  节点数: ${NNODES}"
echo "  节点:   ${NODES[*]}"
echo "  每节点 GPU: ${NPROC_PER_NODE:-8}"
echo "  数据: ${DATA_PATH}"
echo "  模型: ${MODEL_PATH}"

# ===================== 1. 检查免密 SSH =====================

echo ""
echo "--------------------------------------------"
info "[1/4] 检查免密 SSH 连通性..."
echo "--------------------------------------------"

SSH_FAILED=()
for i in "${!NODES[@]}"; do
    ip=${NODES[$i]}
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=no \
           "${SSH_USER}@${ip}" "echo ok" &>/dev/null; then
        ok "node${i} (${ip})"
    else
        fail "node${i} (${ip}) - 无法免密登录"
        SSH_FAILED+=($i)
    fi
done

if [ ${#SSH_FAILED[@]} -gt 0 ]; then
    echo ""
    warn "以下节点需要配置免密 SSH: ${SSH_FAILED[*]}"

    if [ ! -f ~/.ssh/id_rsa ]; then
        info "生成 SSH 密钥对..."
        ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa -q
        ok "密钥生成完成"
    fi

    for i in "${SSH_FAILED[@]}"; do
        ip=${NODES[$i]}
        echo ""
        info "配置 node${i} (${ip}) - 请输入密码:"
        ssh-copy-id -o StrictHostKeyChecking=no "${SSH_USER}@${ip}"
    done

    echo ""
    info "重新验证..."
    for i in "${SSH_FAILED[@]}"; do
        ip=${NODES[$i]}
        if ssh -o BatchMode=yes -o ConnectTimeout=10 "${SSH_USER}@${ip}" "echo ok" &>/dev/null; then
            ok "node${i} (${ip})"
        else
            fail "node${i} (${ip}) 仍然无法连接!"
            echo "请手动检查网络和 SSH 配置后重试"
            exit 1
        fi
    done
fi

ok "所有节点 SSH 连通"

# ===================== 2. 探测网络接口 =====================

echo ""
echo "--------------------------------------------"
info "[2/4] 探测网络接口 (NCCL_SOCKET_IFNAME)..."
echo "--------------------------------------------"

NODE0_IP="${NODES[0]}"
IFNAME=""

LOCAL_IPS=$(hostname -I 2>/dev/null || ip addr show | grep 'inet ' | awk '{print $2}' | cut -d/ -f1)

if echo "$LOCAL_IPS" | grep -qw "$NODE0_IP"; then
    info "当前机器是 node0, 本地探测接口..."
    IFNAME=$(ip -br addr | grep "$NODE0_IP" | awk '{print $1}' | head -1)
else
    info "当前机器不是 node0, SSH 到 node0 探测..."
    IFNAME=$(ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" \
        "ip -br addr | grep '${NODE0_IP}'" 2>/dev/null | awk '{print $1}' | head -1)
fi

if [ -z "$IFNAME" ]; then
    warn "无法通过 IP 反查接口名, 尝试智能探测..."
    _DETECT_CMD='ip -br addr show | grep " UP " | grep -v -E "^(lo|docker|veth|br-|reth)" | awk "\$3 ~ /[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+/ {print \$1}"'
    if echo "$LOCAL_IPS" | grep -qw "$NODE0_IP"; then
        _CANDIDATES=$(eval "$_DETECT_CMD")
    else
        _CANDIDATES=$(ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" "$_DETECT_CMD" 2>/dev/null)
    fi
    IFNAME=$(echo "$_CANDIDATES" | grep -E '^(eth|ens|eno)' | head -1)
    [ -z "$IFNAME" ] && IFNAME=$(echo "$_CANDIDATES" | head -1)
fi

if [ -z "$IFNAME" ]; then
    warn "无法自动检测接口名"
    echo ""
    info "以下是 node0 的网络接口列表 (仅显示有 IP 的):"
    if echo "$LOCAL_IPS" | grep -qw "$NODE0_IP"; then
        ip -br addr show | grep ' UP ' | awk '$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/'
    else
        ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" \
            "ip -br addr show | grep ' UP ' | awk '\$3 ~ /[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/'" 2>/dev/null
    fi
    echo ""
    read -p "  请输入节点间通信的接口名 (如 eth0, ib0, bond0): " IFNAME
fi

ok "网络接口: ${IFNAME}"

# ===================== 3. 探测 InfiniBand =====================

echo ""
echo "--------------------------------------------"
info "[3/4] 检测 InfiniBand / RoCE..."
echo "--------------------------------------------"

IB_DISABLE=1

IB_CHECK_CMD='
if [ -d /sys/class/infiniband ] && [ "$(ls /sys/class/infiniband 2>/dev/null)" ]; then
    echo "IB_FOUND $(ls /sys/class/infiniband)"
elif command -v ibstat &>/dev/null; then
    echo "IB_FOUND ibstat"
else
    echo "IB_NOT_FOUND"
fi
'

IB_RESULT=$(ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" "$IB_CHECK_CMD" 2>/dev/null \
    || eval "$IB_CHECK_CMD")

if echo "$IB_RESULT" | grep -q "IB_FOUND"; then
    IB_DISABLE=0
    IB_DETAIL=$(echo "$IB_RESULT" | sed 's/IB_FOUND //')
    ok "发现 IB 设备 (${IB_DETAIL}) → NCCL_IB_DISABLE=0"
else
    IB_DISABLE=1
    warn "未检测到 IB 设备 → NCCL_IB_DISABLE=1 (走 TCP/IP)"
fi

# ===================== 4. 检测端口 =====================

echo ""
echo "--------------------------------------------"
info "[4/4] 检测通信端口..."
echo "--------------------------------------------"

MASTER_PORT=29500

PORT_CHECK_CMD="ss -tlnp 2>/dev/null | grep -c ':${MASTER_PORT} ' || true"
PORT_USED=$(ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" "$PORT_CHECK_CMD" 2>/dev/null \
    || eval "$PORT_CHECK_CMD")

while [ "${PORT_USED:-0}" -gt 0 ]; do
    warn "端口 ${MASTER_PORT} 被占用, 尝试下一个..."
    MASTER_PORT=$((MASTER_PORT + 1))
    PORT_CHECK_CMD="ss -tlnp 2>/dev/null | grep -c ':${MASTER_PORT} ' || true"
    PORT_USED=$(ssh -o BatchMode=yes "${SSH_USER}@${NODE0_IP}" "$PORT_CHECK_CMD" 2>/dev/null \
        || eval "$PORT_CHECK_CMD")
done

ok "通信端口: ${MASTER_PORT}"

# ===================== 生成 env.sh =====================

echo ""
echo "--------------------------------------------"
info "生成配置文件 ${ENV_FILE}..."
echo "--------------------------------------------"

NPROC=${NPROC_PER_NODE:-8}
TOTAL_GPUS=$((NNODES * NPROC))

NODES_ARRAY_STR=""
for i in "${!NODES[@]}"; do
    NODES_ARRAY_STR+="    \"${NODES[$i]}\"    # node${i}"
    if [ $i -eq 0 ]; then
        NODES_ARRAY_STR+=" (主节点)"
    fi
    NODES_ARRAY_STR+=$'\n'
done

cat > "${ENV_FILE}" << EOF
#!/bin/bash
# ============================================================
# 集群配置 - 由 configure.sh 自动生成
# 生成时间: $(date '+%Y-%m-%d %H:%M:%S')
# 重新生成: bash configure.sh
# ============================================================

SSH_USER="${SSH_USER}"

CLUSTER_NODES=(
${NODES_ARRAY_STR})

NNODES=${NNODES}
NPROC_PER_NODE=${NPROC}
TOTAL_GPUS=${TOTAL_GPUS}

MASTER_ADDR="${NODE0_IP}"
MASTER_PORT=${MASTER_PORT}

NCCL_SOCKET_IFNAME="${IFNAME}"
NCCL_IB_DISABLE=${IB_DISABLE}
GLOO_SOCKET_IFNAME="${IFNAME}"

DATA_PATH="${DATA_PATH}"
MODEL_PATH="${MODEL_PATH}"
OUTPUT_DIR="${OUTPUT_DIR:-./output/qwen3-4b-thinking-sft-multinode}"
EOF

ok "配置已写入 ${ENV_FILE}"

# ===================== 汇总 =====================

echo ""
echo "============================================"
echo -e "  ${GREEN}配置完成!${NC}"
echo "============================================"
echo ""
echo "  节点数:          ${NNODES}"
echo "  每节点 GPU:      ${NPROC}"
echo "  总 GPU 数:       ${TOTAL_GPUS}"
echo "  主节点 (node0):  ${NODE0_IP}"
echo "  通信端口:        ${MASTER_PORT}"
echo "  网络接口:        ${IFNAME}"
echo "  IB 状态:         $([ $IB_DISABLE -eq 0 ] && echo '启用 (高速)' || echo '禁用 (TCP)')"
echo "  数据路径:        ${DATA_PATH}"
echo "  模型:            ${MODEL_PATH}"
echo "  输出目录:        ${OUTPUT_DIR:-./output/qwen3-4b-thinking-sft-multinode}"
echo ""
echo "  下一步:"
echo "    1. bash setup_env.sh        # 本机安装 ms-swift"
echo "    2. bash sync_data.sh        # 同步数据+环境到所有节点"
echo "    3. bash launch_all.sh       # 一键启动训练"
echo "============================================"
