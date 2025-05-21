#!/usr/bin/env python3

import os
import subprocess
from logging_lib import log

class ROSUninstaller:
    """ROS环境卸载工具类"""
    
    @staticmethod
    def uninstall():
        """执行ROS完整卸载流程"""
        log("WARN", "开始卸载ROS环境...")
        
        try:
            # 获取当前ROS发行版
            ros_distro = os.environ.get('ROS_DISTRO')
            if not ros_distro:
                log("WARN", "未检测到ROS_DISTRO环境变量")
                ros_distro = "*"
            
            # 定义要删除的ROS包
            ros_packages = [
                f"ros-{ros_distro}-*",
                "python-rosdep",
                "python-rosinstall",
                "python-rosinstall-generator",
                "python-wstool",
                "python-catkin-tools",
                "python3-rosdep",
                "python3-rosinstall",
                "python3-rosinstall-generator",
                "python3-wstool",
                "python3-catkin-tools"
            ]
            
            # 1. 删除ROS包
            log("INFO", "正在删除ROS相关软件包...")
            subprocess.run(["sudo", "apt-get", "purge", "-y"] + ros_packages,
                         stderr=subprocess.PIPE,
                         stdout=subprocess.PIPE)
            
            # 2. 清理依赖
            log("INFO", "清理自动安装的依赖...")
            subprocess.run(["sudo", "apt-get", "autoremove", "-y"],
                         stderr=subprocess.PIPE,
                         stdout=subprocess.PIPE)
            
            # 3. 删除ROS相关目录
            dirs_to_remove = [
                "/opt/ros",
                "/etc/ros",
                "~/.ros"
            ]
            
            log("INFO", "删除ROS相关目录...")
            for dir_path in dirs_to_remove:
                expanded_path = os.path.expanduser(dir_path)
                if os.path.exists(expanded_path):
                    subprocess.run(["sudo", "rm", "-rf", expanded_path])
                    log("INFO", f"已删除目录: {dir_path}")
            
            # 4. 删除ROS源配置
            ros_source = "/etc/apt/sources.list.d/ros-latest.list"
            if os.path.exists(ros_source):
                subprocess.run(["sudo", "rm", "-f", ros_source])
                log("INFO", "已删除ROS源配置文件")
            
            # 5. 更新包列表
            log("INFO", "更新软件包列表...")
            subprocess.run(["sudo", "apt-get", "update"],
                         stderr=subprocess.PIPE,
                         stdout=subprocess.PIPE)
            
            log("INFO", "ROS环境清理完成")
            log("WARN", "建议重启终端以完全清除ROS环境变量")
            return True
            
        except subprocess.CalledProcessError as e:
            log("ERROR", f"卸载过程出错: {str(e)}")
            return False
        except Exception as e:
            log("ERROR", f"发生未知错误: {str(e)}")
            return False

if __name__ == "__main__":
    # 直接运行时的确认机制
    if input("确定要完全卸载ROS环境吗？这将删除所有ROS相关文件 (y/N): ").lower() == 'y':
        ROSUninstaller.uninstall()
    else:
        log("INFO", "已取消卸载操作")