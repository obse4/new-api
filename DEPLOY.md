# 部署指南

本文档介绍如何使用部署脚本将 new-api 项目部署到远程服务器。

## 前置要求

### 本地环境
- Go 1.19+ 
- Bun (用于构建前端)
- make 工具
- ssh 和 scp 工具
- （可选）sshpass（如果使用密码认证）

### 服务器环境
- Linux 系统（支持 systemd）
- 已配置 SSH 访问
- 具有 sudo 权限的用户

## 快速开始

### 1. 配置 SSH 密钥（推荐方式）

#### 1.1 生成 SSH 密钥对（如果还没有）

```bash
ssh-keygen -t rsa -b 4096 -C "your_email@example.com"
```

按提示操作，默认会在 `~/.ssh/id_rsa`（私钥）和 `~/.ssh/id_rsa.pub`（公钥）。

#### 1.2 将公钥复制到服务器

**方法一：使用 ssh-copy-id（推荐）**
```bash
ssh-copy-id -i ~/.ssh/id_rsa.pub root@your-server-ip
```

**方法二：手动复制**
```bash
# 在本地执行
cat ~/.ssh/id_rsa.pub

# 复制输出的内容，然后在服务器上执行
ssh root@your-server-ip
mkdir -p ~/.ssh
chmod 700 ~/.ssh
echo "你的公钥内容" >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
exit
```

#### 1.3 测试 SSH 连接

```bash
ssh -i ~/.ssh/id_rsa root@your-server-ip
```

如果可以直接登录而无需输入密码，说明配置成功。

### 2. 配置部署脚本

#### 2.1 复制配置文件模板

```bash
cp deploy.config.example deploy.config
```

#### 2.2 编辑配置文件

编辑 `deploy.config` 文件，填入你的服务器信息：

```bash
# 服务器配置
SERVER_HOST="192.168.1.100"  # 修改为你的服务器 IP
SERVER_USER="root"            # 修改为你的 SSH 用户名
SERVER_PORT="22"              # SSH 端口（默认 22）
SERVER_PATH="/usr/local/bin/new-api"

# SSH 认证配置（使用密钥方式）
SSH_KEY_PATH="~/.ssh/id_rsa"  # 你的私钥路径

# 如果使用密码认证（不推荐），取消注释并填写：
# SERVER_PASSWORD="your-password"
```

**重要提示：**
- `deploy.config` 包含敏感信息，不要提交到 Git
- 建议将 `deploy.config` 添加到 `.gitignore`

### 3. 配置 systemd 服务文件

编辑 `new-api.service` 文件，根据你的需求修改：

- `User`: 运行服务的用户（建议使用非 root 用户，如 `www-data` 或创建专用用户）
- `WorkingDirectory`: 工作目录（数据库和日志将存储在这里）
- `ExecStart`: 启动命令和参数

**注意：** 如果使用 SQLite，确保工作目录有写入权限。

### 4. 执行部署

```bash
chmod +x deploy.sh
./deploy.sh
```

部署脚本会自动：
1. 构建 Linux 二进制文件（包含前端资源）
2. 检查服务器环境
3. 上传二进制文件到服务器
4. 配置 systemd 服务
5. 启动服务

### 5. 验证部署

```bash
# 检查服务状态
ssh root@your-server-ip "systemctl status new-api"

# 查看服务日志
ssh root@your-server-ip "journalctl -u new-api -f"

# 检查端口是否监听
ssh root@your-server-ip "netstat -tlnp | grep 3000"
```

## 使用 SQLite 数据库

本项目默认使用 SQLite 数据库。部署脚本会自动创建数据目录 `/data/new-api`。

### SQLite 数据库位置

- 数据库文件：`/data/new-api/one-api.db`
- 日志文件：`/data/new-api/logs/`

### 环境变量配置

如果需要自定义 SQLite 数据库路径，可以在 `new-api.service` 文件中添加环境变量：

```ini
Environment="SQLITE_PATH=/data/new-api/one-api.db"
```

或者通过 `.env` 文件配置（需要在服务器上创建）：

```bash
# 在服务器上创建 .env 文件
ssh root@your-server-ip
cd /data/new-api
cat > .env << EOF
SQLITE_PATH=/data/new-api/one-api.db
SESSION_SECRET=your-random-secret-key
PORT=3000
EOF
```

## 常见问题

### 1. SSH 连接失败

**问题：** `Permission denied (publickey)`

**解决方案：**
- 检查私钥路径是否正确
- 检查私钥文件权限：`chmod 600 ~/.ssh/id_rsa`
- 确认公钥已正确添加到服务器的 `~/.ssh/authorized_keys`

### 2. 构建失败

**问题：** `make linux` 失败

**解决方案：**
- 确保已安装 Go 和 Bun
- 检查前端依赖：`cd web && bun install`
- 检查 Go 模块：`go mod download`

### 3. 服务启动失败

**问题：** `systemctl status new-api` 显示失败

**解决方案：**
- 查看详细日志：`journalctl -u new-api -n 50`
- 检查文件权限：确保二进制文件有执行权限
- 检查工作目录权限：确保服务用户有读写权限
- 检查端口是否被占用：`netstat -tlnp | grep 3000`

### 4. 数据库连接问题

**问题：** SQLite 数据库无法创建或写入

**解决方案：**
- 检查工作目录权限：`chmod 755 /data/new-api`
- 检查 SELinux 状态（如果启用）：`getenforce`
- 确保服务用户有写入权限

### 5. 使用密码认证

如果必须使用密码认证（不推荐），需要安装 `sshpass`：

**macOS:**
```bash
brew install hudochenkov/sshpass/sshpass
```

**Linux:**
```bash
# Ubuntu/Debian
sudo apt-get install sshpass

# CentOS/RHEL
sudo yum install sshpass
```

然后在 `deploy.config` 中配置：
```bash
SERVER_PASSWORD="your-password"
```

## 服务器管理命令

```bash
# 启动服务
sudo systemctl start new-api

# 停止服务
sudo systemctl stop new-api

# 重启服务
sudo systemctl restart new-api

# 查看服务状态
sudo systemctl status new-api

# 查看服务日志
sudo journalctl -u new-api -f

# 查看最近 100 行日志
sudo journalctl -u new-api -n 100

# 启用开机自启
sudo systemctl enable new-api

# 禁用开机自启
sudo systemctl disable new-api
```

## 备份和恢复

### 备份 SQLite 数据库

```bash
# 在服务器上执行
ssh root@your-server-ip
cp /data/new-api/one-api.db /data/new-api/one-api.db.backup.$(date +%Y%m%d_%H%M%S)
```

### 恢复数据库

```bash
# 在服务器上执行
ssh root@your-server-ip
systemctl stop new-api
cp /data/new-api/one-api.db.backup.YYYYMMDD_HHMMSS /data/new-api/one-api.db
systemctl start new-api
```

## 安全建议

1. **使用 SSH 密钥而非密码**：更安全且方便
2. **使用非 root 用户运行服务**：创建专用用户运行服务
3. **配置防火墙**：只开放必要的端口（如 3000）
4. **定期更新**：保持系统和应用更新
5. **备份数据**：定期备份 SQLite 数据库文件
6. **保护配置文件**：不要将 `deploy.config` 提交到版本控制

## 更新部署

当需要更新应用时，只需再次运行部署脚本：

```bash
./deploy.sh
```

脚本会自动：
- 重新构建最新代码
- 停止旧服务
- 上传新二进制文件
- 重启服务

## 故障排查

如果遇到问题，按以下步骤排查：

1. **检查部署脚本输出**：查看是否有错误信息
2. **检查服务器日志**：`journalctl -u new-api -n 100`
3. **检查服务状态**：`systemctl status new-api`
4. **检查网络连接**：确认服务器可以访问
5. **检查文件权限**：确认所有文件有正确的权限

## 联系支持

如果遇到无法解决的问题，请：
1. 查看项目 Issues
2. 提供详细的错误日志
3. 说明你的系统环境（OS、Go 版本等）

