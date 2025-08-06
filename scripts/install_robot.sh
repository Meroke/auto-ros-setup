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
# 脚本 版本
VERSION="v0.1.0"


start_time=$(date +%s.%3N)

# 定义退出时触发的函数
on_exit() {
    end_time=$(date +%s.%3N)
    elapsed=$(echo "scale=3; $end_time - $start_time" | bc)
    
    # 计算分钟和剩余秒数（含小数）
    minutes=$(echo "scale=0; $elapsed / 60" | bc)
    seconds=$(echo "scale=1; $elapsed - ($minutes * 60)" | bc)
    
    # 格式化输出
    if [ "$minutes" -gt 0 ]; then
        echo "脚本总耗时：${minutes}分${seconds}秒"
    else
        echo "脚本总耗时：${seconds}秒"
    fi
}
trap on_exit EXIT

# ============================== 工具层 ==============================
detect_sd_card() {
    log INFO "动态检测SD卡设备..."

    # 使用键值对格式解析设备信息（移除MOUNTPOINT筛选条件）
    local device_info=$(lsblk -p -o NAME,FSTYPE,MOUNTPOINT,TYPE -Ppn 2>/dev/null | \
        awk -F'"' '$4 == "ext4" && ($8 == "part" || $8 == "disk") && $2 ~ /\/dev\/mmcblk1/ {print}')
    local device_name=$(echo "$device_info" | awk -F'"' '{sub(/^NAME=/,"",$2); print $2}')
    log DEBUG "device_name = ${device_name}"
    local device_type=$(echo "$device_info" | awk -F'"' '{sub(/^TYPE=/,"",$8); print $8}')

    if [[ -n "$device_name" && -n "$device_type" ]]; then
        # 新增二次挂载状态检查逻辑 [4,7](@ref)
        local current_mount=$(lsblk -no MOUNTPOINT "$device_name" 2>/dev/null)
        if [[ -n "$current_mount" ]]; then
            log WARN "设备 ${device_name} 已挂载到 $current_mount，不符合未挂载要求"
            echo ${device_name}  # 返回设备名
            return 1
        else
            log INFO "检测到未挂载的ext4设备: [类型:${device_type}] ${device_name}"
            echo ${device_name}  # 返回设备名
            return 0
        fi
    else
        log WARN "未找到符合要求的ext4设备（需满足以下条件）"
        log WARN "- 文件系统类型: ext4"
        log WARN "- 设备类型: 磁盘(disk)或分区(part)"
        return 1
    fi
}

check_filesystem() {
    log INFO "检查SD卡文件系统..."

    # 动态检测设备路径（新增挂载点状态检查）
    local target_device
    if ! target_device=$(detect_sd_card); then
        # 检查挂载点是否已被其他设备占用
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
    KERNELS=="2-1.2:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="Mppcamera"
    KERNELS=="2-1.3:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidarGS2"
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
    # 使用UUID替代设备名
    local device_info=$(lsblk -p -o NAME,FSTYPE,MOUNTPOINT,TYPE,UUID -Ppn 2>/dev/null | \
        awk -F'"' '$4 == "ext4" && ($8 == "part" || $8 == "disk") && $2 ~ /\/dev\/mmcblk1/ {print}')
    local device_uuid=$(echo "$device_info" | awk -F'"' '{print $10}')
    
    # 检查UUID有效性
    if [[ -z "$device_uuid" ]]; then
        log ERROR "未找到符合条件的ext4设备"
        return 1
    fi
    
    # 构造fstab条目（单行无换行符）
    local entry="UUID=${device_uuid} ${SD_CARD_MOUNT_POINT} ext4 defaults,noatime 0 0"
    local regex_pattern=$(echo "${entry}" | sed 's/ /[[:space:]]+/g')

    if sudo grep -qP "^\s*${regex_pattern}\s*$" /etc/fstab 2>/dev/null; then
        log DEBUG "[SUCCESS] 挂载条目 ${entry} 已存在"
        return 0
    else
        # 创建挂载点目录
        sudo mkdir -p "${SD_CARD_MOUNT_POINT}" || { log ERROR "创建目录失败"; return 1; }
        printf "%s\n" "$entry" | sudo tee -a /etc/fstab >/dev/null
        log DEBUG "[SUCCESS] 已添加UUID条目 ${entry} 至/etc/fstab"
        return 0
    fi
}

# ============================== 模块化功能函数 ==============================
install_ros_core() {
    log INFO "开始安装ROS核心组件"
    run_script "${script_dir}/ros.sh" "$SCRIPT_EXECUTOR"
    [[ $? -ne 0 ]] && log ERROR "ROS安装失败" && return 1

    # 安装后，加载环境变量以供后续步骤使用
    log INFO "加载ROS环境变量..."
    local ros_distro
    local ubuntu_version
    ubuntu_version=$(lsb_release -rs)

    if [[ "$ubuntu_version" == "18.04" ]]; then
        ros_distro="melodic"
    elif [[ "$ubuntu_version" == "20.04" ]]; then
        ros_distro="noetic"
    else
        log WARN "未知的 Ubuntu 版本 ($ubuntu_version)，无法加载ROS环境。"
        return 1
    fi

    if [ -n "$ros_distro" ] && [ -f "/opt/ros/${ros_distro}/setup.bash" ]; then
        source "/opt/ros/${ros_distro}/setup.bash"
        log INFO "ROS (distro: ${ros_distro}) 环境已加载到当前会话。"
    else
        log ERROR "ROS setup.bash 文件未找到，后续步骤可能失败。"
        return 1
    fi
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
    # local device="${1:-}" 
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

    echo -e "\e[34m# 文件功能：XIMEI 机器人自动化部署脚本${VERSION}\e[0m"
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
    log INFO "脚本执行结束!"

    # # 操作间隔提示
    # read -p "按回车返回主菜单..."
    # clear
}





main "$@"