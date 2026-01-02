#!/bin/bash

# 部署脚本配置
# 如果存在 deploy.config 文件，则从配置文件读取，否则使用默认值

# 默认配置
SERVER_HOST="your-server-ip-or-hostname"
SERVER_USER="root"
SERVER_PORT="22"
SERVER_PATH="/usr/local/bin/new-api"  # 服务器上二进制文件的路径
SERVICE_NAME="new-api"  # systemd 服务名称

# 本地配置
LOCAL_BINARY="./new-api"  # 本地构建的二进制文件路径
LOCAL_SERVICE_FILE="./new-api.service"  # 本地服务文件路径
REMOTE_SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"  # 服务器上服务文件路径

# 部署选项
AUTO_UPDATE_SYSTEM=true  # 是否自动更新系统（yum update/apt update），设为 false 可加快部署速度

# SSH 认证配置（从配置文件加载，如果没有则使用默认值）
SSH_KEY_PATH=""  # SSH 私钥路径
SERVER_PASSWORD=""  # 服务器密码

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印带颜色的消息
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 如果存在配置文件，则加载配置
if [ -f "./deploy.config" ]; then
    echo -e "${GREEN}[INFO]${NC} 加载配置文件: deploy.config"
    source ./deploy.config
fi

# 验证配置
if [ "$SERVER_HOST" == "your-server-ip-or-hostname" ] && [ ! -f "./deploy.config" ]; then
    echo -e "${RED}[ERROR]${NC} 请配置服务器信息："
    echo -e "${RED}[ERROR]${NC}   1. 复制 deploy.config.example 为 deploy.config"
    echo -e "${RED}[ERROR]${NC}   2. 修改 deploy.config 中的配置"
    echo -e "${RED}[ERROR]${NC}   或者直接在脚本中修改 SERVER_HOST 等变量"
    exit 1
fi

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        print_error "$1 未安装，请先安装 $1"
        exit 1
    fi
}

# 检查必要的命令
check_command "make"
check_command "scp"
check_command "ssh"

# 配置 SSH 认证方式
setup_ssh_auth() {
    # 如果配置了 SSH 密钥，使用密钥认证
    if [ -n "$SSH_KEY_PATH" ]; then
        # 展开 ~ 路径
        SSH_KEY_PATH=$(echo "$SSH_KEY_PATH" | sed "s|^~|$HOME|")
        
        if [ -f "$SSH_KEY_PATH" ]; then
            print_info "使用 SSH 密钥认证: $SSH_KEY_PATH"
            SSH_OPTS="-i $SSH_KEY_PATH -p $SERVER_PORT"
            SCP_OPTS="-i $SSH_KEY_PATH -P $SERVER_PORT"
            return 0
        else
            print_warn "SSH 密钥文件不存在: $SSH_KEY_PATH，将尝试使用密码认证"
        fi
    fi
    
    # 如果配置了密码，使用密码认证（需要 sshpass）
    if [ -n "$SERVER_PASSWORD" ]; then
        print_info "使用密码认证"
        # 检查是否安装了 sshpass
        if ! command -v sshpass &> /dev/null; then
            print_error "使用密码认证需要安装 sshpass"
            print_error "macOS: brew install hudochenkov/sshpass/sshpass"
            print_error "Linux: yum install sshpass 或 apt-get install sshpass"
            print_error "或者配置 SSH 密钥认证（更安全）"
            exit 1
        fi
        SSH_OPTS="-p $SERVER_PORT"
        SCP_OPTS="-P $SERVER_PORT"
        SSH_PASS_CMD="sshpass -p '$SERVER_PASSWORD'"
        SCP_PASS_CMD="sshpass -p '$SERVER_PASSWORD'"
        return 0
    fi
    
    # 都没有配置，使用默认方式（可能需要手动输入密码）
    print_warn "未配置 SSH 密钥或密码，将使用默认认证方式"
    print_warn "如果服务器需要密码，您需要手动输入"
    print_warn "建议配置 SSH_KEY_PATH 或 SERVER_PASSWORD 以自动化部署"
    SSH_OPTS="-p $SERVER_PORT"
    SCP_OPTS="-P $SERVER_PORT"
    SSH_PASS_CMD=""
    SCP_PASS_CMD=""
    return 0
}

# 设置 SSH 认证
setup_ssh_auth

# SSH 命令包装函数
ssh_cmd() {
    if [ -n "$SSH_PASS_CMD" ]; then
        eval "$SSH_PASS_CMD ssh $SSH_OPTS $SERVER_USER@$SERVER_HOST \"$1\""
    else
        ssh $SSH_OPTS "$SERVER_USER@$SERVER_HOST" "$1"
    fi
}

# SCP 命令包装函数
scp_cmd() {
    local src=$1
    local dst=$2
    if [ -n "$SCP_PASS_CMD" ]; then
        eval "$SCP_PASS_CMD scp $SCP_OPTS \"$src\" \"$dst\""
    else
        scp $SCP_OPTS "$src" "$dst"
    fi
}

# 检查服务器上的必要工具和服务
print_info "检查服务器环境..."
check_server_tool() {
    local tool=$1
    local package=$2
    local check_cmd=$3
    
    print_info "检查服务器上是否有 $tool..."
    
    # 检查工具是否存在
    if ssh_cmd "command -v $check_cmd > /dev/null 2>&1"; then
        print_info "$tool 已安装"
        return 0
    else
        print_warn "$tool 未安装，开始安装..."
        
        # 检查是否有 yum
        if ssh_cmd "command -v yum > /dev/null 2>&1"; then
            print_info "检测到 CentOS/RHEL 系统，使用 yum 安装..."
            
            # 更新 yum（根据配置决定是否执行）
            if [ "$AUTO_UPDATE_SYSTEM" == "true" ]; then
                print_info "更新 yum 仓库..."
                if ssh_cmd "yum update -y > /dev/null 2>&1"; then
                    print_info "yum 更新完成"
                else
                    print_warn "yum 更新失败，继续安装..."
                fi
            else
                print_info "跳过系统更新（AUTO_UPDATE_SYSTEM=false）"
            fi
            
            # 安装包
            print_info "安装 $package..."
            if ssh_cmd "yum install -y $package > /dev/null 2>&1"; then
                print_info "$package 安装成功"
                return 0
            else
                print_error "$package 安装失败"
                return 1
            fi
        # 检查是否有 apt (Ubuntu/Debian)
        elif ssh_cmd "command -v apt-get > /dev/null 2>&1"; then
            print_info "检测到 Ubuntu/Debian 系统，使用 apt 安装..."
            
            if [ "$AUTO_UPDATE_SYSTEM" == "true" ]; then
                print_info "更新 apt 仓库..."
                if ssh_cmd "apt-get update -y > /dev/null 2>&1"; then
                    print_info "apt 更新完成"
                else
                    print_warn "apt 更新失败，继续安装..."
                fi
            else
                print_info "跳过系统更新（AUTO_UPDATE_SYSTEM=false）"
            fi
            
            print_info "安装 $package..."
            if ssh_cmd "apt-get install -y $package > /dev/null 2>&1"; then
                print_info "$package 安装成功"
                return 0
            else
                print_error "$package 安装失败"
                return 1
            fi
        else
            print_error "未检测到支持的包管理器（yum 或 apt），请手动安装 $package"
            return 1
        fi
    fi
}

# 检查 systemctl (systemd) - systemd 通常是系统核心组件，只需检查是否可用
print_info "检查服务器上是否有 systemctl..."
if ssh_cmd "command -v systemctl > /dev/null 2>&1"; then
    print_info "systemctl 已安装"
    
    # 检查 systemd 服务是否可用
    print_info "检查 systemd 服务状态..."
    if ssh_cmd "systemctl --version > /dev/null 2>&1"; then
        print_info "systemd 服务可用"
    else
        print_error "systemd 服务不可用，请检查系统配置"
        exit 1
    fi
else
    print_error "systemctl 未找到，systemd 是必需的"
    print_error "如果是 CentOS/RHEL 系统，请手动安装: yum install systemd"
    print_error "如果是 Ubuntu/Debian 系统，请手动安装: apt-get install systemd"
    exit 1
fi

# 确保目标目录存在
print_info "检查服务器目标目录..."
TARGET_DIR=$(dirname "$SERVER_PATH")
if ssh_cmd "test -d $TARGET_DIR"; then
    print_info "目标目录存在: $TARGET_DIR"
else
    print_warn "目标目录不存在，正在创建: $TARGET_DIR"
    if ssh_cmd "mkdir -p $TARGET_DIR"; then
        print_info "目录创建成功"
    else
        print_error "目录创建失败"
        exit 1
    fi
fi

# 确保数据目录存在（用于 SQLite 数据库和日志）
print_info "检查服务器数据目录..."
DATA_DIR="/data/new-api"
if ssh_cmd "test -d $DATA_DIR"; then
    print_info "数据目录存在: $DATA_DIR"
else
    print_warn "数据目录不存在，正在创建: $DATA_DIR"
    if ssh_cmd "mkdir -p $DATA_DIR"; then
        print_info "数据目录创建成功"
        # 设置适当的权限
        ssh_cmd "chmod 755 $DATA_DIR" 2>/dev/null || true
    else
        print_error "数据目录创建失败"
        exit 1
    fi
fi

print_info "服务器环境检查完成"

# 步骤1: 构建二进制文件
print_info "开始构建 Linux 二进制文件..."
if make linux; then
    print_info "构建成功: $LOCAL_BINARY"
else
    print_error "构建失败，请检查错误信息"
    exit 1
fi

# 检查二进制文件是否存在
if [ ! -f "$LOCAL_BINARY" ]; then
    print_error "二进制文件不存在: $LOCAL_BINARY"
    exit 1
fi

# 步骤2: 检查并上传 systemd 服务文件
print_info "检查服务器上的 systemd 服务文件..."
SERVICE_EXISTS=$(ssh_cmd "test -f $REMOTE_SERVICE_FILE && echo 'yes' || echo 'no'")

if [ "$SERVICE_EXISTS" == "no" ]; then
    print_warn "服务器上不存在服务文件: $REMOTE_SERVICE_FILE"
    
    # 检查本地服务文件是否存在
    if [ ! -f "$LOCAL_SERVICE_FILE" ]; then
        print_error "本地服务文件不存在: $LOCAL_SERVICE_FILE"
        print_error "请确保项目根目录存在 new-api.service 文件"
        exit 1
    fi
    
    print_info "上传服务文件到服务器..."
    if scp_cmd "$LOCAL_SERVICE_FILE" "$SERVER_USER@$SERVER_HOST:$REMOTE_SERVICE_FILE"; then
        print_info "服务文件上传成功"
        
        # 重新加载 systemd 配置
        print_info "重新加载 systemd 配置..."
        if ssh_cmd "systemctl daemon-reload"; then
            print_info "systemd 配置重新加载成功"
            
            # 启用服务（开机自启）
            print_info "启用服务（开机自启）..."
            if ssh_cmd "systemctl enable $SERVICE_NAME"; then
                print_info "服务已启用"
            else
                print_warn "启用服务失败，但可以继续部署"
            fi
        else
            print_error "重新加载 systemd 配置失败"
            exit 1
        fi
    else
        print_error "服务文件上传失败"
        exit 1
    fi
else
    print_info "服务器上已存在服务文件，跳过上传"
fi

# 步骤3: 停止服务（先停止服务以便替换二进制文件）
print_info "停止 systemd 服务: $SERVICE_NAME..."
if ssh_cmd "systemctl stop $SERVICE_NAME"; then
    print_info "服务已停止"
else
    print_warn "停止服务时出现错误（可能服务未运行）"
fi

# 等待服务完全停止
sleep 2

# 步骤4: 上传二进制文件到服务器（使用临时文件名，然后原子性替换）
TEMP_BINARY_PATH="${SERVER_PATH}.tmp"
print_info "上传文件到临时位置: $TEMP_BINARY_PATH..."
if scp_cmd "$LOCAL_BINARY" "$SERVER_USER@$SERVER_HOST:$TEMP_BINARY_PATH"; then
    print_info "文件上传成功"
    
    # 原子性移动到目标位置
    print_info "移动文件到目标位置..."
    if ssh_cmd "mv $TEMP_BINARY_PATH $SERVER_PATH"; then
        print_info "文件移动成功"
    else
        print_error "文件移动失败"
        # 清理临时文件
        ssh_cmd "rm -f $TEMP_BINARY_PATH" 2>/dev/null
        exit 1
    fi
else
    print_error "文件上传失败"
    exit 1
fi

# 步骤5: 设置执行权限
print_info "设置文件执行权限..."
if ssh_cmd "chmod +x $SERVER_PATH"; then
    print_info "执行权限设置成功"
else
    print_error "执行权限设置失败"
    exit 1
fi

# 步骤6: 启动服务
print_info "启动 systemd 服务: $SERVICE_NAME..."
if ssh_cmd "systemctl start $SERVICE_NAME"; then
    print_info "服务启动成功"
else
    print_error "服务启动失败"
    exit 1
fi

# 步骤7: 检查服务状态
print_info "检查服务状态..."
sleep 1
if ssh_cmd "systemctl status $SERVICE_NAME --no-pager -l"; then
    print_info "部署完成！"
else
    print_warn "无法获取服务状态，请手动检查"
fi

print_info "部署流程完成！"
print_info "提示：SQLite 数据库文件将存储在服务器的 $DATA_DIR 目录中"
print_info "提示：日志文件将存储在服务器的 $DATA_DIR/logs 目录中（如果配置了日志目录）"

