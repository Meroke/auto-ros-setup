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
            configure_rosdep
            install_project_components
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