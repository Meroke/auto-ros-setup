#!/bin/bash
# Jetson专用ROS环境配置脚本（支持多Ubuntu版本）
# 依赖：需先source logging_lib.sh

set -euo pipefail
source ./logging_lib.sh

# # 动态获取系统信息
readonly UBUNTU_VERSION=$(lsb_release -rs)  # 18.04/20.04等
readonly UBUNTU_CODENAME=$(lsb_release -sc) # bionic/focal等
readonly TSINGHUA_SOURCE_URL="https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
declare -A ROS_VERSION_MAP=(
    ["18.04"]="melodic"
    ["20.04"]="noetic"
)
ROS_VERSION=${ROS_VERSION_MAP[$UBUNTU_VERSION]}

# export UBUNTU_VERSION, UBUNTU_CODENAME, ROS_VERSION

# 校验支持的Ubuntu版本
validate_ubuntu_version() {
    if [[ -z "$ROS_VERSION" ]]; then
        log ERROR "不支持的Ubuntu版本: $UBUNTU_VERSION (仅支持18.04/20.04)"
        exit 1
    fi
}

# 硬件架构检查
check_architecture() {
    local arch
    arch=$(uname -m)
    if [ "$arch" != "aarch64" ]; then
        log ERROR "本脚本仅适用于ARM64架构设备"
        exit 1
    fi
}

# 配置清华源（动态适配版本）
setup_tsinghua_source() {
    log INFO "开始配置清华镜像源（Ubuntu $UBUNTU_CODENAME）..."
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    
    sudo tee /etc/apt/sources.list > /dev/null <<EOF
# 清华大学镜像源（Ubuntu ${UBUNTU_CODENAME^} for ARM）
deb ${TSINGHUA_SOURCE_URL} ${UBUNTU_CODENAME} main restricted universe multiverse
deb ${TSINGHUA_SOURCE_URL} ${UBUNTU_CODENAME}-updates main restricted universe multiverse
deb ${TSINGHUA_SOURCE_URL} ${UBUNTU_CODENAME}-backports main restricted universe multiverse
deb ${TSINGHUA_SOURCE_URL} ${UBUNTU_CODENAME}-security main restricted universe multiverse
EOF

    log INFO "清华源配置完成"
}

# 安装ROS基础环境（动态适配版本）
install_ros_base() {
    log INFO "开始安装ROS ${ROS_VERSION} (适配Ubuntu ${UBUNTU_CODENAME^}) ..."
    
    # 添加ROS镜像源
    log INFO "添加ROS清华镜像源"
    sudo sh -c "echo 'deb [arch=arm64] http://mirrors.tuna.tsinghua.edu.cn/ros/ubuntu/ ${UBUNTU_CODENAME} main' > /etc/apt/sources.list.d/ros-latest.list"

    # 添加ROS密钥
    log INFO "添加ROS GPG密钥"
    sudo apt-key adv --keyserver 'hkp://keyserver.ubuntu.com:80' --recv-key C1CF6E31E6BADE8868B172B4F42ED6FBAB17C654

    # 安装核心组件
    log INFO "更新软件源"
    sudo apt update -qq
    
    log INFO "安装ROS基础包"
    # 公共安装部分
    sudo apt install -y "ros-${ROS_VERSION}-ros-base"
    
    # 特殊版本处理
    if [[ $ROS_VERSION == "melodic" ]]; then
        sudo apt install -y python-rosinstall
    fi

    # 环境配置
    log INFO "配置bash环境"
    # 定义匹配标识（检查注释行是否存在）
    if ! grep -q "# ROS ${ROS_VERSION} 配置" ~/.bashrc; then
        echo -e "\n# ROS ${ROS_VERSION} 配置" >> ~/.bashrc
        echo "source /opt/ros/${ROS_VERSION}/setup.bash" >> ~/.bashrc
    fi
}

# 单机ROS环境配置
setup_ros_env() {
    local bashrc_file="${HOME}/.bashrc"
    local marker="# ROS single-machine configuration"
    local ros_ip="127.0.0.1"
    
    # 定义环境变量配置
    local env_config=(
        "export ROS_HOSTNAME=${ros_ip}"
        "export ROS_MASTER_URI=http://${ros_ip}:11311"
    )
    
    log INFO "配置单机ROS环境..."
    
    # 检查是否已存在配置
    if grep -qF "ROS_MASTER_URI=http://127.0.0.1:11311" "$bashrc_file"; then
        log INFO "[已存在] 单机ROS配置无需修改"
        return 0
    fi
    
    # 添加带注释的配置块
    log INFO "写入单机ROS配置到 ${bashrc_file}"
    {
        echo -e "\n${marker}"
        printf '%s\n' "${env_config[@]}"
        echo -e "# ${marker} end\n"
    } >> "$bashrc_file"
    
    log INFO "[成功] 单机ROS环境已配置："
    log INFO "$(printf '%s\n' "${env_config[@]}")"
}

check_ros_installation() {
    log INFO "检查 ROS 环境..."
    local ros_path="/opt/ros/${ROS_VERSION}"

    # 1. 增强的ROS安装检查（修复严格模式问题）
    if [[ ! -d "$ros_path" ]]; then
        log ERROR "未检测到ROS ${ROS_VERSION}安装，路径不存在: $ros_path"
        log WARN "正在尝试自动安装ROS环境..."
        
        # 新增安装流程（处理严格模式问题）
        if ! wget http://fishros.com/install -O fishros; then
            log ERROR "下载安装脚本失败，请检查网络连接"
            exit 1
        fi
        
        log INFO "开始交互式安装，请根据提示操作..."
        # 修复点：临时关闭严格模式并允许交互
        ( 
            set +u  # 关闭未定义变量检查
            bash fishros  # 使用bash执行而不是source
        ) || {
            log ERROR "自动安装过程失败"
            exit 1
        }

        # 安装后二次验证（增加延迟等待）
        sleep 5  # 等待系统更新
        if [[ ! -d "$ros_path" ]]; then
            log ERROR "自动安装后仍未检测到ROS，可能原因："
            log ERROR "1. 安装过程中断"
            log ERROR "2. 系统源配置错误"
            log ERROR "请尝试手动安装："
            log ERROR "curl -s https://fishros.com/install | bash"
            exit 1
        fi
    fi

    set +u
    log DEBUG "尝试加载环境变量: $ros_path/setup.bash"
    if ! source "$ros_path/setup.bash"; then
        log ERROR "环境初始化失败，详细错误："
        set -u
        source "$ros_path/setup.bash" 2>&1 | sed 's/^/  | /' >&2
        exit 1
    fi
    set -u
    # export ROS_DISTRO=${ROS_VERSION}
    log DEBUG "ROS_DISTRO=${ROS_DISTRO}"

    # 4. 核心组件检查（兼容ros-base版）
    local required_commands=(rosrun rospack rosmsg)
    for cmd in "${required_commands[@]}"; do
        if ! type -p "$cmd" >/dev/null; then
            log ERROR "核心组件缺失 - 未找到命令: $cmd"
            log WARN "当前安装的是ros-base版本，建议补充安装:"
            log WARN "sudo apt install ros-${ROS_DISTRO}-ros-base"
            exit 1
        fi
    done

    log INFO "ROS环境验证通过 (版本: ${ROS_DISTRO})"
}

# 主流程调整
main() {
    validate_ubuntu_version  # 新增版本校验
    check_architecture
    log WARN "本操作将修改系统APT源配置"
    log WARN "原始配置已备份至 /etc/apt/sources.list.bak"
    
    setup_tsinghua_source
    install_ros_base
    setup_ros_env

    # 自动生效配置
    log INFO "正在自动生效环境配置..."
    if ! source ~/.bashrc; then
        log ERROR "环境配置加载失败，请手动执行：source ~/.bashrc"
        exit 1
    fi
    log INFO "安装完成！当前环境已生效。"
    log INFO "系统信息：Ubuntu ${UBUNTU_CODENAME^} ${UBUNTU_VERSION} | ROS ${ROS_VERSION}"
    # ROS 环境检查 (在文件系统检查之后，确保在正确的文件系统环境下)
    check_ros_installation
}
main "$@"