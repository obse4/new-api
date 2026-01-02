#!/bin/bash

# Fork 项目上游同步脚本
# 用于自动同步上游仓库代码并合并到当前项目

set -e  # 遇到错误立即退出

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# 检查是否在 Git 仓库中
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    print_error "当前目录不是 Git 仓库"
    exit 1
fi

# 检查是否有 upstream 远程仓库
if ! git remote | grep -q upstream; then
    print_warn "未找到 upstream 远程仓库"
    read -p "是否添加上游仓库? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        read -p "请输入上游仓库 URL: " UPSTREAM_URL
        git remote add upstream "$UPSTREAM_URL"
        print_info "已添加上游仓库: $UPSTREAM_URL"
    else
        print_error "请先配置 upstream 远程仓库"
        exit 1
    fi
fi

# 步骤 1: 检查工作区状态
print_step "1. 检查工作区状态..."
if [ -n "$(git status --porcelain)" ]; then
    print_warn "工作区有未提交的更改"
    git status --short
    echo
    read -p "是否暂存当前更改? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git stash push -m "Auto-stash before sync $(date +%Y-%m-%d_%H:%M:%S)"
        print_info "更改已暂存"
        STASHED=true
    else
        print_error "请先提交或暂存更改"
        exit 1
    fi
else
    print_info "工作区干净"
    STASHED=false
fi

# 步骤 2: 切换到主分支
print_step "2. 切换到主分支..."
CURRENT_BRANCH=$(git branch --show-current)
if [ "$CURRENT_BRANCH" != "main" ]; then
    print_info "从 $CURRENT_BRANCH 切换到 main"
    git checkout main
else
    print_info "已在 main 分支"
fi

# 步骤 3: 更新本地主分支
print_step "3. 更新本地主分支..."
if git pull origin main; then
    print_info "本地主分支已更新"
else
    print_error "拉取远程主分支失败"
    exit 1
fi

# 步骤 4: 获取上游代码
print_step "4. 获取上游代码..."
if git fetch upstream main; then
    print_info "上游代码已获取"
else
    print_error "获取上游代码失败"
    exit 1
fi

# 步骤 5: 检查是否有更新
UPSTREAM_COMMITS=$(git rev-list HEAD..upstream/main --count)
if [ "$UPSTREAM_COMMITS" -eq 0 ]; then
    print_info "上游没有新更新，无需同步"
    if [ "$STASHED" = true ]; then
        git stash pop
    fi
    exit 0
else
    print_info "检测到 $UPSTREAM_COMMITS 个新提交"
fi

# 步骤 6: 创建合并分支
print_step "6. 创建合并分支..."
BRANCH_NAME="merge-upstream-$(date +%Y%m%d-%H%M%S)"
if git checkout -b "$BRANCH_NAME"; then
    print_info "已创建合并分支: $BRANCH_NAME"
else
    print_error "创建分支失败"
    exit 1
fi

# 步骤 7: 合并上游代码
print_step "7. 合并上游代码..."
if git merge upstream/main --no-edit; then
    print_info "合并成功，无冲突"
    HAS_CONFLICTS=false
else
    print_warn "检测到合并冲突"
    HAS_CONFLICTS=true
    
    # 显示冲突文件
    CONFLICT_FILES=$(git diff --name-only --diff-filter=U)
    print_warn "冲突文件列表:"
    echo "$CONFLICT_FILES" | sed 's/^/  - /'
    
    echo
    print_warn "请手动解决冲突后，运行以下命令:"
    echo "  git add ."
    echo "  git commit -m 'Merge upstream/main: resolved conflicts'"
    echo "  git checkout main"
    echo "  git merge $BRANCH_NAME"
    echo "  git push origin main"
    echo "  git branch -d $BRANCH_NAME"
    
    if [ "$STASHED" = true ]; then
        print_info "恢复暂存的更改..."
        git stash pop || true
    fi
    
    exit 1
fi

# 步骤 8: 测试构建
print_step "8. 测试构建..."
if command -v make > /dev/null 2>&1; then
    if make linux; then
        print_info "构建成功"
    else
        print_error "构建失败，请检查错误"
        git checkout main
        git branch -D "$BRANCH_NAME"
        if [ "$STASHED" = true ]; then
            git stash pop
        fi
        exit 1
    fi
else
    print_warn "未找到 make 命令，跳过构建测试"
fi

# 步骤 9: 提交合并
print_step "9. 提交合并..."
if [ "$HAS_CONFLICTS" = false ]; then
    # 检查是否有需要提交的更改
    if [ -n "$(git status --porcelain)" ]; then
        git add .
        git commit -m "Merge upstream/main - $(date +%Y-%m-%d_%H:%M:%S)"
        print_info "合并已提交"
    else
        print_info "无需提交（可能已经是最新的）"
    fi
fi

# 步骤 10: 合并到主分支
print_step "10. 合并到主分支..."
git checkout main
if git merge "$BRANCH_NAME" --no-edit; then
    print_info "已合并到主分支"
else
    print_error "合并到主分支失败"
    exit 1
fi

# 步骤 11: 推送到远程
print_step "11. 推送到远程仓库..."
read -p "是否推送到远程仓库? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if git push origin main; then
        print_info "已推送到远程仓库"
    else
        print_error "推送失败"
        exit 1
    fi
else
    print_warn "跳过推送，你可以稍后手动推送: git push origin main"
fi

# 步骤 12: 清理
print_step "12. 清理临时分支..."
git branch -d "$BRANCH_NAME"
print_info "临时分支已删除"

# 恢复暂存的更改
if [ "$STASHED" = true ]; then
    print_info "恢复暂存的更改..."
    git stash pop || print_warn "恢复暂存更改时出现问题，请手动检查: git stash list"
fi

# 完成
echo
print_info "✅ 同步完成！"
echo
print_info "摘要:"
echo "  - 合并了 $UPSTREAM_COMMITS 个上游提交"
echo "  - 当前分支: $(git branch --show-current)"
echo "  - 最新提交: $(git log -1 --oneline)"
echo
print_info "下一步:"
echo "  1. 测试应用功能"
echo "  2. 如果一切正常，运行部署脚本: ./deploy.sh"

