#!/data/data/com.termux/files/usr/bin/bash

# AutoGLM 命令修复脚本
# 用于修复 autoglm 命令不可用的问题

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info "正在修复 autoglm 命令..."

# 确保 HOME 变量已设置
if [ -z "$HOME" ]; then
    export HOME="/data/data/com.termux/files/home"
fi

# 确保 bin 目录存在
if [ ! -d "$HOME/bin" ]; then
    print_info "创建 $HOME/bin 目录..."
    mkdir -p "$HOME/bin" || {
        print_error "无法创建 $HOME/bin 目录"
        exit 1
    }
fi

# 检查 autoglm 脚本是否存在
if [ ! -f "$HOME/bin/autoglm" ]; then
    print_error "autoglm 脚本不存在: $HOME/bin/autoglm"
    print_info "请先运行部署脚本: ./deploy.sh"
    exit 1
fi

# 确保脚本有执行权限
chmod +x "$HOME/bin/autoglm"
print_success "已设置 autoglm 脚本执行权限"

# 确保 ~/bin 在 PATH 中
if ! echo "$PATH" | grep -q "$HOME/bin"; then
    print_info "将 $HOME/bin 添加到 PATH..."
    export PATH="$PATH:$HOME/bin"
    
    # 添加到 .bashrc（如果还没有）
    if ! grep -q "export PATH=\$PATH:\$HOME/bin" ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo '# AutoGLM 命令路径' >> ~/.bashrc
        echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
        print_success "已将 PATH 配置添加到 ~/.bashrc"
    fi
else
    print_info "$HOME/bin 已在 PATH 中"
fi

# 验证命令是否可用
if command -v autoglm &> /dev/null; then
    print_success "autoglm 命令已修复并可用！"
    echo ""
    echo "命令位置: $(which autoglm)"
    echo ""
    echo "现在可以使用 autoglm 命令了:"
    echo "  autoglm"
    echo ""
else
    print_warning "autoglm 命令仍然不可用"
    echo ""
    echo "请尝试以下方法:"
    echo "  1. 重新打开 Termux 终端"
    echo "  2. 运行: source ~/.bashrc"
    echo "  3. 手动运行: export PATH=\$PATH:\$HOME/bin"
    echo ""
    echo "验证脚本是否存在:"
    echo "  ls -l $HOME/bin/autoglm"
    echo ""
    exit 1
fi

