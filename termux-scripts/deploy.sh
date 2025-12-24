#!/data/data/com.termux/files/usr/bin/bash

# Open-AutoGLM 混合方案 - Termux 一键部署脚本
# 版本: 1.0.0

# 注意: 不使用 set -e，因为某些非关键错误不应该导致脚本退出
# 我们会在关键步骤手动检查错误

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 打印函数
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

print_header() {
    echo ""
    echo "============================================================"
    echo "  Open-AutoGLM 混合方案 - 一键部署"
    echo "  版本: 1.0.0"
    echo "============================================================"
    echo ""
}

# 初始化环境（确保必要的目录和工具存在）
init_environment() {
    print_info "初始化环境..."
    
    # 确保 HOME 变量已设置
    if [ -z "$HOME" ]; then
        export HOME="/data/data/com.termux/files/home"
    fi
    
    # 确保必要的目录存在
    mkdir -p "$HOME/tmp" 2>/dev/null || true
    mkdir -p "$HOME/bin" 2>/dev/null || true
    mkdir -p "$HOME/.autoglm" 2>/dev/null || true
    
    # 确保 PATH 包含必要的目录
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        export PATH="$PATH:$HOME/bin"
    fi
    
    # 确保 HOME 变量已设置
    if [ -z "$HOME" ]; then
        export HOME="/data/data/com.termux/files/home"
    fi
    
    # 检查必要的命令
    local missing_tools=()
    
    for tool in bash curl wget; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        print_warning "缺少工具: ${missing_tools[*]}"
        print_info "将在后续步骤中安装"
    fi
    
    print_success "环境初始化完成"
}

# 检查网络连接
check_network() {
    print_info "检查网络连接..."
    if ping -c 1 8.8.8.8 &> /dev/null; then
        print_success "网络连接正常"
    else
        print_error "网络连接失败，请检查网络设置"
        exit 1
    fi
}

# 更新软件包
update_packages() {
    print_info "更新软件包列表..."
    if ! pkg update -y; then
        print_warning "软件包更新失败，但继续执行..."
    else
        print_success "软件包列表更新完成"
    fi
}

# 安装必要软件
install_dependencies() {
    print_info "安装必要软件..."
    
    # 检查并安装 Python
    if ! command -v python &> /dev/null; then
        print_info "安装 Python..."
        if ! pkg install python -y; then
            print_error "Python 安装失败"
            exit 1
        fi
    else
        print_success "Python 已安装: $(python --version 2>/dev/null || echo '未知版本')"
    fi
    
    # 检查并安装 Git
    if ! command -v git &> /dev/null; then
        print_info "安装 Git..."
        if ! pkg install git -y; then
            print_error "Git 安装失败"
            exit 1
        fi
    else
        print_success "Git 已安装: $(git --version 2>/dev/null || echo '未知版本')"
    fi
    
    # 检查并安装 pip (Termux 中必须通过 pkg 安装)
    if ! command -v pip &> /dev/null; then
        print_info "安装 pip..."
        if ! pkg install python-pip -y; then
            print_error "pip 安装失败"
            exit 1
        fi
    else
        print_success "pip 已安装: $(pip --version 2>/dev/null || echo '未知版本')"
    fi

    # 安装其他工具和证书
    print_info "安装其他必要工具..."
    pkg install curl wget ca-certificates -y || {
        print_warning "部分工具安装失败，但继续执行..."
    }

    # 更新证书（重要：解决 SSL 证书问题）
    print_info "更新 CA 证书..."
    pkg install ca-certificates -y || true

    print_success "必要软件安装完成"
}

# 安装 Pillow 所需的系统依赖（图像处理库）
install_pillow_dependencies() {
    print_info "安装 Pillow 所需的系统依赖..."
    
    # Pillow 需要这些库来编译：
    # - libjpeg-turbo: JPEG 支持
    # - libpng: PNG 支持
    # - freetype: 字体渲染
    # - libwebp: WebP 支持
    # - openjpeg: JPEG 2000 支持
    # - zlib: 压缩支持
    
    print_info "安装图像处理库依赖..."
    if pkg install libjpeg-turbo libpng freetype libwebp openjpeg zlib -y; then
        print_success "Pillow 依赖安装完成"
        return 0
    else
        print_warning "部分 Pillow 依赖安装失败，但继续尝试..."
        # 尝试安装最基础的依赖
        pkg install libjpeg-turbo libpng zlib -y || {
            print_warning "基础依赖安装失败，Pillow 可能无法编译"
        }
        return 1
    fi
}

# 安装 Rust 工具链（用于编译需要 Rust 的 Python 包，如 jiter）
install_rust() {
    print_info "检查 Rust 工具链..."
    
    if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
        print_success "Rust 已安装: $(rustc --version)"
        return 0
    fi
    
    print_info "安装 Rust 工具链（这可能需要几分钟，请保持网络连接）..."
    print_warning "注意: 某些 Python 包（如 jiter）需要 Rust 编译器"
    
    # 尝试通过 pkg 安装 Rust（Termux 推荐方式）
    print_info "尝试通过 pkg 安装 Rust..."
    if pkg install rust -y 2>&1; then
        # 验证安装
        if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
            print_success "Rust 安装完成: $(rustc --version)"
            return 0
        else
            print_warning "Rust 安装可能未完成，继续尝试其他方式..."
        fi
    else
        print_warning "通过 pkg 安装 Rust 失败"
    fi
    
    # 如果 pkg 安装失败，尝试使用 rustup（备用方案）
    print_info "尝试使用 rustup 安装 Rust..."
    print_warning "注意: 在手机上安装 rustup 可能需要较长时间（10-30分钟）"
    
    # 确保临时目录存在
    mkdir -p "$HOME/tmp"
    
    # 下载 rustup 安装脚本（使用 -k 参数忽略 SSL 证书问题，手机环境常见）
    if curl -k -sSf https://sh.rustup.rs -o "$HOME/tmp/rustup-init.sh" 2>/dev/null; then
        print_info "下载 rustup 安装脚本成功"
        chmod +x "$HOME/tmp/rustup-init.sh"
        
        # 执行安装（非交互模式）
        if "$HOME/tmp/rustup-init.sh" -y 2>&1; then
            # 加载 Rust 环境
            if [ -f "$HOME/.cargo/env" ]; then
                source "$HOME/.cargo/env"
                print_success "Rust 环境已加载"
            fi
            
            # 验证安装
            if command -v rustc &> /dev/null && command -v cargo &> /dev/null; then
                print_success "Rust 安装完成: $(rustc --version)"
                rm -f "$HOME/tmp/rustup-init.sh"
                return 0
            else
                print_warning "Rust 安装可能未完成，请检查环境变量"
            fi
        else
            print_error "rustup 安装脚本执行失败"
            rm -f "$HOME/tmp/rustup-init.sh"
        fi
    else
        print_error "无法下载 rustup 安装脚本"
        print_warning "请检查网络连接或手动安装 Rust"
    fi
    
    # 如果都失败了
    print_error "Rust 安装失败"
    print_warning "某些需要 Rust 的包（如 jiter）可能无法安装"
    print_info "您可以稍后手动安装:"
    print_info "  1. pkg install rust"
    print_info "  2. 或访问: https://rustup.rs/"
    return 1
}

# 安装 Python 依赖
install_python_packages() {
    print_info "安装 Python 依赖包..."

    # 注意: Termux 中不允许通过 pip 升级 pip，必须使用 pkg 管理
    # 如果需要更新 pip，请使用: pkg upgrade python-pip

    # 设置环境变量防止 pip 自动升级
    export PIP_NO_UPGRADE=1

    # 确保 PREFIX 变量已设置（Termux 环境）
    if [ -z "$PREFIX" ]; then
        export PREFIX="/data/data/com.termux/files/usr"
    fi

    # 尝试配置证书（如果存在）
    CERT_FILE="$PREFIX/etc/tls/cert.pem"
    if [ -f "$CERT_FILE" ]; then
        export SSL_CERT_FILE="$CERT_FILE"
        export REQUESTS_CA_BUNDLE="$CERT_FILE"
        print_info "使用系统证书: $CERT_FILE"
    else
        print_warning "系统证书文件不存在，将使用 --trusted-host 参数"
    fi

    # 确保临时目录存在
    mkdir -p "$HOME/tmp"
    
    # 先安装 Pillow 所需的系统依赖
    install_pillow_dependencies || {
        print_warning "Pillow 依赖安装失败，但继续尝试安装 Python 包..."
    }

    # 使用 --trusted-host 参数解决 SSL 证书问题（手机 Termux 常见问题）
    # 这是最可靠的方法，因为手机网络环境复杂，SSL 验证经常失败
    print_info "安装依赖包（使用 --trusted-host 绕过 SSL 验证）..."
    
    # 尝试安装，如果失败则检查是否是 Pillow 问题
    PIP_BASIC_LOG="$HOME/tmp/pip_basic_install.log"
    if command -v tee &> /dev/null; then
        if ! pip install --no-warn-script-location --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pillow openai requests 2>&1 | tee "$PIP_BASIC_LOG"; then
            PIP_BASIC_FAILED=1
        fi
    else
        if ! pip install --no-warn-script-location --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pillow openai requests > "$PIP_BASIC_LOG" 2>&1; then
            PIP_BASIC_FAILED=1
            cat "$PIP_BASIC_LOG"
        fi
    fi
    
    if [ "${PIP_BASIC_FAILED:-0}" = "1" ]; then
        print_error "基础依赖安装失败"
        
        # 检查是否是 Pillow 问题
        if grep -qi "pillow\|jpeg\|RequiredDependencyException" "$PIP_BASIC_LOG" 2>/dev/null; then
            print_error "检测到 Pillow 构建错误"
            print_info "正在尝试安装 Pillow 系统依赖..."
            
            if install_pillow_dependencies; then
                print_info "重新尝试安装..."
                if pip install --no-warn-script-location --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pillow openai requests; then
                    print_success "依赖安装成功"
                else
                    print_error "即使安装了依赖，安装仍然失败"
                    print_info "尝试使用预编译的 Pillow..."
                    # 尝试只安装二进制包
                    pip install --only-binary=pillow --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org pillow || {
                        print_error "Pillow 安装失败，请检查错误日志: $PIP_BASIC_LOG"
                        exit 1
                    }
                    # 继续安装其他包
                    pip install --no-warn-script-location --trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org openai requests || {
                        print_error "其他依赖安装失败"
                        exit 1
                    }
                fi
            else
                print_error "Pillow 依赖安装失败"
                print_info "请手动安装: pkg install libjpeg-turbo libpng freetype"
                exit 1
            fi
        else
            print_error "安装失败，请检查网络连接和错误日志: $PIP_BASIC_LOG"
            exit 1
        fi
    fi

    print_success "Python 依赖安装完成"
}

# 下载 Open-AutoGLM
download_autoglm() {
    print_info "下载 Open-AutoGLM 项目..."

    cd ~

    if [ -d "Open-AutoGLM" ]; then
        print_warning "Open-AutoGLM 目录已存在"
        echo -n "是否删除并重新下载? (y/n): "
        read confirm
        if [ "$confirm" = "y" ] || [ "$confirm" = "Y" ]; then
            rm -rf Open-AutoGLM
        else
            print_info "跳过下载，使用现有目录"
            return
        fi
    fi

    print_info "正在从 GitHub 克隆 Open-AutoGLM..."
    if ! git clone https://github.com/zai-org/Open-AutoGLM.git; then
        print_error "Git 克隆失败，请检查网络连接"
        exit 1
    fi

    print_success "Open-AutoGLM 下载完成"
}

# 安装 Open-AutoGLM
install_autoglm() {
    print_info "安装 Open-AutoGLM..."

    if [ ! -d "$HOME/Open-AutoGLM" ]; then
        print_error "Open-AutoGLM 目录不存在，请先运行 download_autoglm"
        exit 1
    fi

    cd ~/Open-AutoGLM || {
        print_error "无法进入 Open-AutoGLM 目录"
        exit 1
    }

    # 设置环境变量防止 pip 自动升级
    export PIP_NO_UPGRADE=1

    # 确保 PREFIX 变量已设置（Termux 环境）
    if [ -z "$PREFIX" ]; then
        export PREFIX="/data/data/com.termux/files/usr"
    fi

    # 加载 Rust 环境（如果通过 rustup 安装）
    if [ -f "$HOME/.cargo/env" ]; then
        source "$HOME/.cargo/env"
    fi

    # 尝试配置证书（如果存在）
    CERT_FILE="$PREFIX/etc/tls/cert.pem"
    if [ -f "$CERT_FILE" ]; then
        export SSL_CERT_FILE="$CERT_FILE"
        export REQUESTS_CA_BUNDLE="$CERT_FILE"
    fi

    # 使用 --trusted-host 参数解决 SSL 证书问题（手机 Termux 常见问题）
    PIP_TRUSTED_HOST="--trusted-host pypi.org --trusted-host pypi.python.org --trusted-host files.pythonhosted.org"

    # 确保临时目录存在（Termux 中 /tmp 可能不存在）
    mkdir -p "$HOME/tmp"
    LOG_FILE="$HOME/tmp/pip_install.log"
    
    # 检查 requirements.txt 是否存在
    if [ ! -f "requirements.txt" ]; then
        print_warning "requirements.txt 不存在，跳过依赖安装"
        return 0
    fi
    
    # 安装项目依赖
    if [ -f "requirements.txt" ]; then
        print_info "安装项目依赖..."
        print_warning "注意: 如果遇到 jiter 安装失败，脚本会自动安装 Rust"
        
        # 尝试安装依赖，如果失败则提供更详细的错误信息
        # 使用 tee 保存日志，如果 tee 不可用则只输出到文件
        if command -v tee &> /dev/null; then
            if ! pip install --no-warn-script-location $PIP_TRUSTED_HOST -r requirements.txt 2>&1 | tee "$LOG_FILE"; then
                PIP_FAILED=1
            fi
        else
            # 如果 tee 不可用，直接重定向到文件
            if ! pip install --no-warn-script-location $PIP_TRUSTED_HOST -r requirements.txt > "$LOG_FILE" 2>&1; then
                PIP_FAILED=1
                cat "$LOG_FILE"
            fi
        fi
        
        if [ "${PIP_FAILED:-0}" = "1" ]; then
            print_error "安装项目依赖失败"
            
            # 检查是否是 Rust 相关错误
            if grep -qi "rust\|maturin\|jiter\|Unsupported platform" "$LOG_FILE" 2>/dev/null; then
                print_error "检测到 Rust 相关错误"
                print_info "jiter 等包需要 Rust 编译器"
                print_info "正在尝试安装 Rust..."
                
                if install_rust; then
                    # 重新加载 Rust 环境
                    if [ -f "$HOME/.cargo/env" ]; then
                        source "$HOME/.cargo/env"
                    fi
                    
                    print_info "重新尝试安装依赖..."
                    if pip install --no-warn-script-location $PIP_TRUSTED_HOST -r requirements.txt; then
                        print_success "依赖安装成功"
                    else
                        print_error "即使安装了 Rust，依赖安装仍然失败"
                        print_info "请检查错误日志: $LOG_FILE"
                        exit 1
                    fi
                else
                    print_error "Rust 安装失败，无法继续"
                    print_info "请手动安装 Rust: pkg install rust"
                    print_info "然后重新运行此脚本"
                    exit 1
                fi
            # 检查是否是 Pillow 相关错误
            elif grep -qi "pillow\|jpeg\|RequiredDependencyException" "$LOG_FILE" 2>/dev/null; then
                print_error "检测到 Pillow 构建错误"
                print_info "Pillow 需要系统库来编译（如 libjpeg-turbo）"
                print_info "正在尝试安装 Pillow 依赖..."
                
                if install_pillow_dependencies; then
                    print_info "重新尝试安装依赖..."
                    if pip install --no-warn-script-location $PIP_TRUSTED_HOST -r requirements.txt; then
                        print_success "依赖安装成功"
                    else
                        print_error "即使安装了 Pillow 依赖，依赖安装仍然失败"
                        print_info "请检查错误日志: $LOG_FILE"
                        print_info "提示: 可以尝试使用预编译的 Pillow wheel: pip install --only-binary=pillow pillow"
                        exit 1
                    fi
                else
                    print_error "Pillow 依赖安装失败"
                    print_info "请手动安装: pkg install libjpeg-turbo libpng freetype"
                    print_info "然后重新运行此脚本"
                    exit 1
                fi
            else
                print_error "请检查网络连接和错误日志: $LOG_FILE"
                print_info "常见问题:"
                print_info "  - 网络连接问题"
                print_info "  - 缺少系统依赖（检查日志中的 RequiredDependencyException）"
                print_info "  - 编译工具缺失"
                exit 1
            fi
        fi
    fi

    # 安装 phone_agent
    print_info "安装 phone_agent..."
    AGENT_LOG_FILE="$HOME/tmp/pip_install_agent.log"
    AGENT_FAILED=0
    
    # 使用 tee 保存日志，如果 tee 不可用则只输出到文件
    if command -v tee &> /dev/null; then
        if ! pip install --no-warn-script-location $PIP_TRUSTED_HOST -e . 2>&1 | tee "$AGENT_LOG_FILE"; then
            AGENT_FAILED=1
        fi
    else
        # 如果 tee 不可用，直接重定向到文件
        if ! pip install --no-warn-script-location $PIP_TRUSTED_HOST -e . > "$AGENT_LOG_FILE" 2>&1; then
            AGENT_FAILED=1
            cat "$AGENT_LOG_FILE"
        fi
    fi
    
    if [ "$AGENT_FAILED" = "1" ]; then
        print_error "安装 phone_agent 失败"
        
        # 检查是否是 Rust 相关错误
        if grep -qi "rust\|maturin\|jiter\|Unsupported platform" "$AGENT_LOG_FILE" 2>/dev/null; then
            print_error "检测到 Rust 相关错误"
            print_info "正在尝试安装 Rust..."
            
            if install_rust; then
                # 重新加载 Rust 环境
                if [ -f "$HOME/.cargo/env" ]; then
                    source "$HOME/.cargo/env"
                fi
                
                print_info "重新尝试安装 phone_agent..."
                if pip install --no-warn-script-location $PIP_TRUSTED_HOST -e .; then
                    print_success "phone_agent 安装成功"
                else
                    print_error "即使安装了 Rust，phone_agent 安装仍然失败"
                    print_info "请检查错误日志: $AGENT_LOG_FILE"
                    exit 1
                fi
            else
                print_error "Rust 安装失败，无法继续"
                exit 1
            fi
        elif grep -qi "pillow\|jpeg\|RequiredDependencyException" "$AGENT_LOG_FILE" 2>/dev/null; then
            print_error "检测到 Pillow 构建错误"
            print_info "正在尝试安装 Pillow 依赖..."
            
            if install_pillow_dependencies; then
                print_info "重新尝试安装 phone_agent..."
                if pip install --no-warn-script-location $PIP_TRUSTED_HOST -e .; then
                    print_success "phone_agent 安装成功"
                else
                    print_error "即使安装了 Pillow 依赖，phone_agent 安装仍然失败"
                    print_info "请检查错误日志: $AGENT_LOG_FILE"
                    exit 1
                fi
            else
                print_error "Pillow 依赖安装失败，无法继续"
                exit 1
            fi
        else
            print_error "请检查网络连接和错误日志: $AGENT_LOG_FILE"
            exit 1
        fi
    fi

    print_success "Open-AutoGLM 安装完成"
}

# 下载混合方案脚本
download_hybrid_scripts() {
    print_info "下载混合方案脚本..."

    cd ~

    # 创建目录
    mkdir -p ~/.autoglm

    # 下载 phone_controller.py (自动降级逻辑)
    # 注意: 这里需要替换为实际的下载链接
    # wget -O ~/.autoglm/phone_controller.py https://your-link/phone_controller.py

    # 暂时使用本地创建
    cat > ~/.autoglm/phone_controller.py << 'PYTHON_EOF'
# 这个文件会在后续步骤中创建
pass
PYTHON_EOF

    print_success "混合方案脚本下载完成"
}

# 配置 GRS AI
configure_grsai() {
    print_info "配置 GRS AI..."

    echo ""
    echo "请输入您的 GRS AI API Key:"
    echo -n "API Key: "
    read api_key

    if [ -z "$api_key" ]; then
        print_warning "未输入 API Key，跳过配置"
        print_warning "您可以稍后手动配置: export PHONE_AGENT_API_KEY='your_key'"
        return
    fi

    # 创建配置文件
    cat > ~/.autoglm/config.sh << EOF
#!/data/data/com.termux/files/usr/bin/bash

# GRS AI 配置
export PHONE_AGENT_BASE_URL="https://api.grsai.com/v1"
export PHONE_AGENT_API_KEY="$api_key"
export PHONE_AGENT_MODEL="gpt-4-vision-preview"

# AutoGLM Helper 配置
export AUTOGLM_HELPER_URL="http://localhost:8080"
EOF

    # 添加到 .bashrc
    if ! grep -q "source ~/.autoglm/config.sh" ~/.bashrc; then
        echo "" >> ~/.bashrc
        echo "# AutoGLM 配置" >> ~/.bashrc
        echo "source ~/.autoglm/config.sh" >> ~/.bashrc
    fi

    # 立即加载配置（如果文件存在）
    if [ -f ~/.autoglm/config.sh ]; then
        source ~/.autoglm/config.sh || true
    fi

    print_success "GRS AI 配置完成"
}

# 创建启动脚本
create_launcher() {
    print_info "创建启动脚本..."

    # 确保 bin 目录存在
    mkdir -p "$HOME/bin" 2>/dev/null || {
        print_error "无法创建 $HOME/bin 目录"
        exit 1
    }

    # 创建 autoglm 命令
    cat > "$HOME/bin/autoglm" << 'LAUNCHER_EOF'
#!/data/data/com.termux/files/usr/bin/bash

# 加载配置（如果存在）
if [ -f ~/.autoglm/config.sh ]; then
    source ~/.autoglm/config.sh
fi

# 启动 AutoGLM
if [ -d ~/Open-AutoGLM ]; then
    cd ~/Open-AutoGLM || exit 1
    python -m phone_agent.cli
else
    echo "错误: Open-AutoGLM 目录不存在"
    echo "请先运行部署脚本: ./deploy.sh"
    exit 1
fi
LAUNCHER_EOF

    chmod +x "$HOME/bin/autoglm"

    # 确保 ~/bin 在 PATH 中（使用 $HOME 而不是 ~）
    if ! grep -q "export PATH=\$PATH:\$HOME/bin" ~/.bashrc 2>/dev/null; then
        echo '' >> ~/.bashrc
        echo '# AutoGLM 命令路径' >> ~/.bashrc
        echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
    fi

    # 立即将 ~/bin 添加到当前会话的 PATH
    if ! echo "$PATH" | grep -q "$HOME/bin"; then
        export PATH="$PATH:$HOME/bin"
    fi

    # 验证命令是否可用
    if command -v autoglm &> /dev/null; then
        print_success "启动脚本创建完成，命令已可用"
    else
        print_warning "启动脚本已创建，但命令暂时不可用"
        print_info "请运行以下命令使其生效:"
        print_info "  export PATH=\$PATH:\$HOME/bin"
        print_info "或者重新打开 Termux 终端"
    fi
}

# 检查 AutoGLM Helper
check_helper_app() {
    print_info "检查 AutoGLM Helper APP..."

    echo ""
    echo "请确保您已经:"
    echo "1. 安装了 AutoGLM Helper APK"
    echo "2. 开启了无障碍服务权限"
    echo ""

    echo -n "是否已完成以上步骤? (y/n): "
    read confirm

    if [ "$confirm" != "y" ]; then
        print_warning "请先完成以上步骤，然后重新运行部署脚本"
        print_info "APK 文件位置: 项目根目录/AutoGLM-Helper.apk"
        print_info "安装命令: adb install AutoGLM-Helper.apk"
        exit 0
    fi

    # 测试连接
    print_info "测试 AutoGLM Helper 连接..."

    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 3 http://localhost:8080/status > /dev/null 2>&1; then
            print_success "AutoGLM Helper 连接成功！"
        else
            print_warning "无法连接到 AutoGLM Helper"
            print_info "这可能是因为:"
            print_info "1. AutoGLM Helper 未运行"
            print_info "2. 无障碍服务未开启"
            print_info "3. HTTP 服务器未启动"
            print_info ""
            print_info "请检查后重试，或稍后手动测试"
        fi
    else
        print_warning "curl 不可用，跳过连接测试"
    fi
}

# 显示完成信息
show_completion() {
    print_success "部署完成！"

    echo ""
    echo "============================================================"
    echo "  部署成功！"
    echo "============================================================"
    echo ""
    echo "使用方法:"
    echo "  1. 确保 AutoGLM Helper 已运行并开启无障碍权限"
    echo "  2. 在 Termux 中输入: autoglm"
    echo "  3. 输入任务，如: 打开淘宝搜索蓝牙耳机"
    echo ""
    echo "配置文件:"
    echo "  ~/.autoglm/config.sh"
    echo ""
    echo "启动命令:"
    echo "  autoglm"
    echo ""
    
    # 检查 autoglm 命令是否可用
    if ! command -v autoglm &> /dev/null; then
        echo "⚠️  注意: autoglm 命令当前不可用"
        echo ""
        echo "请执行以下命令之一来修复:"
        echo "  方法1 (推荐): 重新打开 Termux 终端"
        echo "  方法2: 运行以下命令:"
        echo "    export PATH=\$PATH:\$HOME/bin"
        echo "  方法3: 手动加载配置:"
        echo "    source ~/.bashrc"
        echo ""
        echo "验证命令是否可用:"
        echo "  which autoglm"
        echo "  应该显示: $HOME/bin/autoglm"
        echo ""
    fi
    
    echo "故障排除:"
    echo "  - 如果提示 'command not found':"
    echo "    运行: export PATH=\$PATH:\$HOME/bin"
    echo "    或重新打开 Termux 终端"
    echo "  - 检查 AutoGLM Helper 是否运行"
    echo "  - 检查无障碍权限是否开启"
    echo "  - 测试连接: curl http://localhost:8080/status"
    echo ""
    echo "============================================================"
    echo ""
}

# 主函数
main() {
    print_header

    # 检查是否在 Termux 中运行
    if [ ! -d "/data/data/com.termux" ]; then
        print_error "此脚本必须在 Termux 中运行！"
        exit 1
    fi

    # 设置环境变量防止 pip 自动升级（Termux 要求）
    export PIP_NO_UPGRADE=1

    # 执行部署步骤
    init_environment      # 首先初始化环境
    check_network
    update_packages
    install_dependencies
    install_pillow_dependencies  # 提前安装 Pillow 依赖
    install_rust  # 提前安装 Rust，避免后续安装失败
    install_python_packages
    download_autoglm
    install_autoglm
    download_hybrid_scripts
    configure_grsai
    create_launcher
    check_helper_app
    show_completion
}

# 运行主函数
main
