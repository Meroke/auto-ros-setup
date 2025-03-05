#!/bin/bash
set -euo pipefail
# ========================================================================
# 创建时间：2025-02-28
# 版本号：1.0
# 文件功能：XIMEI 机器人自动化部署脚本
# ========================================================================
# 
# ██╗  ██╗██╗███╗   ███╗███████╗██╗
# ╚██╗██╔╝██║████╗ ████║██╔════╝██║
#  ╚███╔╝ ██║██╔████╔██║█████╗  ██║
#  ██╔██╗ ██║██║╚██╔╝██║██╔══╝  ██║
# ██╔╝ ██╗██║██║ ╚═╝ ██║███████╗██╗
# ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝
#                                       
# ======================= 版本说明 ========================
# version 1.0
#   - 适配ubuntu18.04 
#         ubuntu20.04
#   - 实现基础部署功能
#   - 支持SD卡自动挂载
#   - 集成ROS环境配置
#   - 包含依赖库自动安装
#
# install_robot.sh：主部署脚本，包含文件系统检查、ROS环境配置、脚本执行流程
# rosdep.sh：处理rosdep配置，更新数据库
# robot_robot.sh：构建机器人工作空间，安装SDK和依赖库
# logging_lib.sh：提供日志功能
# ========================================================
# ============================== 配置层 ==============================
source ./logging_lib.sh

# SD卡设备路径 (动态检测), 初始为空，将在 check_filesystem 中动态赋值
SD_CARD_DEVICE=""
# SD卡挂载点，固定为 /mnt/sdcard
SD_CARD_MOUNT_POINT="/mnt/sdcard"
# 子脚本执行器，默认为 bash， 可选 source
SCRIPT_EXECUTOR="${2:-bash}"


# ============================== 工具层 ==============================

detect_sd_card() {
    log INFO "动态检测SD卡设备..."
    
    # 使用键值对格式解析设备信息
    local device_info=$(lsblk -o NAME,FSTYPE,MOUNTPOINT,TYPE -Ppn 2>/dev/null | \
        awk -F'"' '$4 == "ext4" && $6 == "" && ($8 == "part" || $8 == "disk") {print; exit}')

    # 提取设备名（完整路径如 /dev/mmcblk1）
    local device=$(echo "$device_info" | awk -F'"' '{print $2}' | sed 's/NAME=//')

    # 提取设备类型（disk/part）
    local device_type=$(echo "$device_info" | awk -F'"' '{print $8}' | sed 's/TYPE=//')

    if [[ -n "$device" && -n "$device_type" ]]; then
        echo "$device"  # 输出完整设备路径（如 /dev/mmcblk1）
        log INFO "检测到未挂载的ext4设备: [类型:${device_type}] ${device}"
    else
        log WARN "未找到符合要求的ext4设备（需满足以下条件）"
        log WARN "- 文件系统类型: ext4"
        log WARN "- 设备类型: 磁盘(disk)或分区(part)"
        log WARN "- 挂载状态: 未挂载"
        return 1
    fi
}

check_filesystem() {
    log INFO "检查SD卡文件系统..."

    # 动态检测设备路径（新增挂载点状态检查）
    local target_device
    if ! target_device=$(detect_sd_card); then
        # 关键修改点：检查挂载点是否已被其他设备占用
        if mount | grep -q "${SD_CARD_MOUNT_POINT}"; then
            log INFO "挂载点 ${SD_CARD_MOUNT_POINT} 已被使用, 继续执行"
            return 0
        else
            log ERROR "终止条件：未找到未挂载设备且挂载点未被使用"
            exit 1
        fi
    fi

    SD_CARD_DEVICE="$target_device"
    log INFO "检测到设备: ${SD_CARD_DEVICE}"

    # 挂载点状态检查（新增设备与挂载点关联性验证）[2,7](@ref)
    if mount | grep -q "^${SD_CARD_DEVICE}.*${SD_CARD_MOUNT_POINT}"; then
        log INFO "设备已正确挂载到 ${SD_CARD_MOUNT_POINT}"
        return 0
    elif mount | grep -q "${SD_CARD_MOUNT_POINT}"; then
        log WARN "挂载点被其他设备占用，建议手动处理冲突"
        exit 1
    fi

    # 创建挂载目录（增加权限检查）[7,9](@ref)
    [[ ! -d "${SD_CARD_MOUNT_POINT}" ]] && \
        sudo mkdir -p "${SD_CARD_MOUNT_POINT}" && \
        sudo chmod 755 "${SD_CARD_MOUNT_POINT}"

    # 挂载操作（增加异常捕获）[3,8](@ref)
    if ! sudo mount -t ext4 -o defaults,nofail "${SD_CARD_DEVICE}" "${SD_CARD_MOUNT_POINT}"; then
        log ERROR "挂载失败，可能原因："
        log ERROR "1. 设备格式异常（建议用 fsck 检查）[5,8](@ref)"
        log ERROR "2. 设备已被其他进程占用（使用 lsof 检查）[4](@ref)"
        exit 1
    fi
}



run_script() {
    local script_path=$1
    local script_name=$(basename "$script_path")

    [[ -f "$script_path" ]] || {
        log ERROR "脚本不存在: ${script_path}"
        exit 1
    }

    log INFO "执行脚本: ${script_name}"
    
    # 使用当前shell环境执行
    (
        set -euo pipefail
        source "$script_path"
    ) || {
        log ERROR "脚本执行失败: ${script_name}"
        exit 1
    }
    log INFO "脚本 ${script_name} 执行完成" # 添加执行完成日志
}

# 函数：创建 udev 规则并重载服务
setup_udev_rules() {
    # 写入规则文件
    log INFO "正在创建 /etc/udev/rules.d/robot.rules..."
    readonly UBUNTU_VERSION=$(lsb_release -rs)

    log INFO "检测到的 Ubuntu 版本: ${UBUNTU_VERSION}"

    if [ "$UBUNTU_VERSION" = "18.04" ]; then
        # 如果系统是 ubuntu18.04
        log INFO "写入 Ubuntu 18.04 对应的 robot.rules 内容..."
        sudo tee /etc/udev/rules.d/robot.rules >/dev/null <<EOF
    KERNELS=="1-2.2:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="wheeltec_controller"
    KERNELS=="1-2.1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidar"
    KERNELS=="1-2.3:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidarGS2"
EOF
        log INFO "Ubuntu 18.04 对应的 robot.rules 内容已写入。"
    elif [ "$UBUNTU_VERSION" = "20.04" ]; then
        # 如果系统是 ubuntu20.04
        log INFO "写入 Ubuntu 20.04 对应的 robot.rules 内容..."
        sudo tee /etc/udev/rules.d/robot.rules >/dev/null <<EOF
    KERNELS=="2-1.1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="wheeltec_controller"
    KERNELS=="3-1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidar"
    KERNELS=="2-1.2:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidarGS2"
EOF
        log INFO "Ubuntu 20.04 对应的 robot.rules 内容已写入。"
    else
        # 如果 Ubuntu 版本既不是 18.04 也不是 20.04，则给出提示
        log WARN "警告：检测到的 Ubuntu 版本 '${UBUNTU_VERSION}' 既不是 18.04 也不是 20.04。"
        log WARN "      未知的 Ubuntu 版本，将不会自动写入 robot.rules 文件。"
        log WARN "      请手动检查并配置 /etc/udev/rules.d/robot.rules 文件。"
    fi

    # 重载 udev 服务
    log INFO "重载 udev 规则..."
    sudo service udev reload || { log ERROR "重载服务失败"; exit 1; }
    log INFO "重启 udev 服务..."
    sudo service udev restart || { log ERROR "重启服务失败"; exit 1; }

    log INFO "操作完成，请重新插拔设备验证符号链接"
}

check_fstab_entry() {
    log INFO "检查SD卡挂载是否持久化..."
    # 定义目标条目（注意空格和参数顺序）
    local entry="/dev/mmcblk1p1 /mnt/sdcard ext4 defaults,noatime 0 0"
    
    # 转换为兼容正则表达式（处理任意数量空格/制表符）
    local regex_pattern=$(echo "$entry" | sed 's/[[:space:]]+/[[:space:]]+/g')
    
    # 带权限检查的精确匹配
    if sudo grep -qP "^\s*${regex_pattern}\s*$" /etc/fstab 2>/dev/null; then
        log INFO "[SUCCESS] SD卡挂载已持久化, 位于/etc/fstab" >&2
        return 0
    else
        # 错误处理分支
        if [[ $? -eq 2 ]]; then
            log ERROR "/etc/fstab 文件不存在或权限不足" >&2
            return 1
        else
            log INFO "条目未找到，正在自动添加..." >&2
            echo "$entry" | sudo tee -a /etc/fstab >/dev/null
            if [[ $? -eq 0 ]]; then
                log INFO "[SUCCESS] 已添加条目: ${entry} 到/etc/fstab" >&2  # 修改此处
                return 0
            else
                log ERROR "[FAILED] 添加条目失败" >&2
                return 1
            fi
        fi
    fi
}

# ============================== 模块化功能函数 ==============================
install_ros_core() {
    log INFO "开始安装ROS核心组件"
    run_script "${script_dir}/ros.sh" "$SCRIPT_EXECUTOR"
    [[ $? -ne 0 ]] && log ERROR "ROS安装失败" && return 1
    log INFO "ROS核心安装完成"
}

configure_rosdep() {
    log INFO "初始化rosdep依赖管理"
    run_script "${script_dir}/rosdep.sh" "$SCRIPT_EXECUTOR"
    if [[ $? -eq 0 ]]; then
        log INFO "rosdep配置成功"
        rosdep update
    else
        log WARN "rosdep初始化异常"
    fi
    log INFO "rosdep配置完成"
}

install_project_components() {
    log INFO "安装机器人专用组件"
    run_script "${script_dir}/robot_robot.sh" "$SCRIPT_EXECUTOR"
    [[ $? -eq 0 ]] && log INFO "机器人组件安装完成" || log ERROR "组件安装失败"
}

uninstall_ros() {
    log WARN "开始卸载ROS组件"
    run_script "${script_dir}/uninstall_ros.sh" "$SCRIPT_EXECUTOR"
    [[ $? -eq 0 ]] && log INFO "ROS卸载完成" || log ERROR "卸载过程出现错误"
}


# ============================== 主流程控制函数 ==============================
main() {
    local device="${1:-}" 
    local executor="${2:-bash}"
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    
    # 初始化全局变量
    SCRIPT_EXECUTOR="$executor"
    COMPILE_CACHE="${script_dir}/.build_cache"  # 编译文件缓存目录

    # 彩色图标与标题
    echo -e "\e[36m
    # ██╗  ██╗██╗███╗   ███╗███████╗██╗
    # ╚██╗██╔╝██║████╗ ████║██╔════╝██║
    #  ╚███╔╝ ██║██╔████╔██║█████╗  ██║
    #  ██╔██╗ ██║██║╚██╔╝██║██╔══╝  ██║
    # ██╔╝ ██╗██║██║ ╚═╝ ██║███████╗██╗
    # ╚═╝  ╚═╝╚═╝╚═╝     ╚═╝╚══════╝╚═╝
    \e[0m"

    echo -e "\e[34m# 文件功能：XIMEI 机器人自动化部署脚本\e[0m"
    echo -e "\e[34m# ========================================================================\e[0m\n"

    # 彩色菜单函数
    echo -e "\e[33m请选择操作 (输入数字或 q 退出):\e[0m"
    echo -e "  \e[32m1.\e[0m 全流程安装"
    echo -e "  \e[32m2.\e[0m 安装ROS核心"
    echo -e "  \e[32m3.\e[0m 配置rosdep依赖"
    echo -e "  \e[32m4.\e[0m 安装robot_robot项目依赖"
    echo -e "  \e[32m5.\e[0m 完全卸载ros并清理build/devel"
    read -p "➤ " choice


    case $choice in
        1)  # 全流程安装
            log INFO "启动全自动安装流程"
            install_ros_core
            check_filesystem
            setup_udev_rules
            configure_rosdep
            install_project_components
            check_fstab_entry
            ;;
        2)  # 仅安装ROS
            install_ros_core
            ;;
        3)  # 配置rosdep
            configure_rosdep
            ;;
        4)  # 项目组件
            install_project_components
            ;;
        5)  # 卸载清理
            uninstall_ros
            clean_compilation_cache
            ;;
        q|Q) 
            log INFO "退出安装程序"
            exit 0
            ;;
        *) 
            echo "无效输入，请重新选择"
            continue
            ;;
    esac

    # # 操作间隔提示
    # read -p "按回车返回主菜单..."
    # clear
}





main "$@"