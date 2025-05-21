#!/usr/bin/env python3
import os
import sys
import subprocess
import time
from logging_lib import log  # 导入日志模块
import robot_robot
import rosdep
from ros_uninstaller import ROSUninstaller

# ============================== 配置层 ==============================
# 脚本执行器，默认使用bash，可通过命令行参数指定
SCRIPT_EXECUTOR = sys.argv[2] if len(sys.argv) > 2 else "bash"
# 脚本版本号
VERSION = "v0.1.0"
# 脚本开始时间，用于计算总耗时
start_time = time.time()

# 定义退出时触发的函数，计算并显示脚本运行时间
def on_exit():
    end_time = time.time()
    elapsed = end_time - start_time
    minutes = int(elapsed / 60)
    seconds = elapsed % 60
    if minutes > 0:
        log("INFO", f"脚本总耗时：{minutes}分{seconds:.1f}秒")
    else:
        log("INFO", f"脚本总耗时：{seconds:.1f}秒")

# 注册退出函数，确保脚本结束时执行
import atexit
atexit.register(on_exit)

# ============================== 工具层 ==============================
def run_script(script_path):
    """执行子脚本的函数"""
    script_name = os.path.basename(script_path)
    if not os.path.isfile(script_path):
        log("ERROR", f"脚本不存在: {script_path}")
        sys.exit(1)
    
    log("INFO", f"执行脚本: {script_name}")
    try:
        subprocess.run([SCRIPT_EXECUTOR, script_path], check=True)
        log("INFO", f"脚本 {script_name} 执行完成")
    except subprocess.CalledProcessError:
        log("ERROR", f"脚本执行失败: {script_name}")
        sys.exit(1)

# ============================== 模块化功能函数 ==============================
def check_ros_core():
    """检查ROS核心组件是否正确安装"""
    log("INFO", "检查ROS环境...")
    # 检查ROS安装目录
    ros_path = "/opt/ros"
    if not os.path.exists(ros_path):
        log("ERROR", "未检测到ROS安装目录 (/opt/ros)，请先安装ROS")
        return False
    
    # 检查ROS发行版目录
    ros_distros = [d for d in os.listdir(ros_path) if os.path.isdir(os.path.join(ros_path, d))]
    if not ros_distros:
        log("ERROR", "ROS安装目录存在但未找到任何ROS发行版")
        return False
    
    log("INFO", f"检测到已安装的ROS发行版: {', '.join(ros_distros)}")
    return True



def configure_rosdep():
    """配置rosdep依赖管理"""
    log("INFO", "初始化rosdep依赖管理")
    rosdep_setup = RosdepSetup()
    if rosdep_setup.setup():
        log("INFO", "rosdep配置成功")
    else:
        log("ERROR", "rosdep配置失败")

def install_project_components():
    """配置dm_ws项目"""
    log("INFO", "配置dm_ws项目")
    robot_setup = RobotSetup()
    if robot_setup.setup():
        log("INFO", "配置dm_ws项目成功")
    else:
        log("ERROR", "配置dm_ws项目失败")

def uninstall_ros():
    """卸载ROS组件"""
    if input("确定要完全卸载ROS吗？这将删除所有ROS相关文件 (y/N): ").lower() == 'y':
        if ROSUninstaller.uninstall():
            log("INFO", "ROS卸载成功")
        else:
            log("ERROR", "ROS卸载过程中出现错误")
    else:
        log("INFO", "已取消卸载操作")

# ============================== 主流程控制函数 ==============================
def main():
    """主函数，控制脚本执行流程"""
    global script_dir
    # 获取脚本所在目录
    script_dir = os.path.dirname(os.path.abspath(__file__))

    # 显示彩色标题和图标
    print("\033[36m")  # 青色
    print(r'''
    # ██████╗  ██████╗ ███████╗
    # ██╔══██╗██╔═══██╗██╔════╝
    # ██████╔╝██║   ██║███████╗
    # ██╔══██╗██║   ██║╚════██║
    # ██║  ██║╚██████╔╝███████║
    # ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
    ''')
    print("\033[0m")  # 重置颜色
    print(f"\033[34m# 文件功能：ROS自动化部署脚本 {VERSION}\033[0m")
    print("\033[34m# ========================================================================\033[0m\n")
    
    while True:
        # 显示彩色菜单
        print("\033[33m请选择操作 (输入数字或 q 退出):\033[0m")
        print("  \033[32m1.\033[0m 全流程安装")
        print("  \033[32m2.\033[0m 安装ROS核心")
        print("  \033[32m3.\033[0m 配置rosdep依赖")
        print("  \033[32m4.\033[0m 安装robot_robot项目依赖")
        print("  \033[32m5.\033[0m 完全卸载ros并清理build/devel")
        choice = input("➤ ")

        # 根据用户选择执行对应操作
        if choice == "1":
            log("INFO", "启动全自动安装流程")
            check_ros_core()
            configure_rosdep()
            install_project_components()
        elif choice == "2":
            check_ros_core()
        elif choice == "3":
            configure_rosdep()
        elif choice == "4":
            install_project_components()
        elif choice == "5":
            uninstall_ros()
        elif choice.lower() == "q":
            log("INFO", "退出安装程序")
            sys.exit(0)
        else:
            print("无效输入，请重新选择")
            continue

        log("INFO", "脚本执行结束!")
        input("按回车返回主菜单...")
        os.system("clear")

if __name__ == "__main__":
    main()