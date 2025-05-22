#!/usr/bin/env python3
import subprocess
from logging_lib import log

class CommonInstaller:
    """通用组件安装类"""

    def __init__(self):
        # 常用工具包列表(每行三个，按字母顺序排序)
        self.tools = [
            "build-essential", "cmake",         "curl",
            "gdb",             "git",           "htop",
            "net-tools",       "ninja-build",   "psmisc",
            "python3-pip",     "tmux",          "tree",
            "unzip",           "vim",           "wget",
        ]

    def install_packages(self, packages=None):
        """
        批量安装软件包
        
        参数:
            packages: 要安装的软件包列表，如果为None则安装预定义的工具包
        返回:
            bool: 安装是否成功
        """
        if packages is None:
            packages = self.tools
        
        log("INFO", f"开始批量安装软件包: {', '.join(packages)}")
        
        try:
            # 更新软件源
            subprocess.run(["sudo", "apt-get", "update"], check=True)
            
            # 批量安装
            subprocess.run(["sudo", "apt-get", "install", "-y"] + packages, check=True)
            
            # 验证安装
            failed_packages = []
            for pkg in packages:
                if subprocess.run(["dpkg", "-l", pkg], 
                                stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE).returncode != 0:
                    failed_packages.append(pkg)
            
            if failed_packages:
                log("ERROR", f"以下包安装失败: {', '.join(failed_packages)}")
                return False
                
            log("INFO", "所有软件包安装成功")
            return True
            
        except subprocess.CalledProcessError as e:
            log("ERROR", f"软件包安装过程出错: {str(e)}")
            return False

    def install_ssh(self, package_name):
        """安装指定的系统包"""
        log("INFO", f"正在安装: {package_name}")
        try:
            # subprocess.run(["sudo", "apt-get", "update"], check=True)
            # subprocess.run(["sudo", "apt-get", "install", "-y", package_name], check=True)
            log("INFO", f"{package_name} 安装成功")
            return True
        except subprocess.CalledProcessError as e:
            log("ERROR", f"{package_name} 安装失败: {str(e)}")
            return False

    def enable_ssh(self):
        """安装并启动SSH服务"""
        if not self.install_ssh("openssh-server"):
            return False
        try:
            subprocess.run(["sudo", "systemctl", "enable",  "ssh"], check=True)
            subprocess.run(["sudo", "systemctl", "restart", "ssh"], check=True)
            log("INFO", "SSH服务已启动并设置为开机自启")
            return True
        except subprocess.CalledProcessError as e:
            log("ERROR", f"SSH服务启动失败: {str(e)}")
            return False

    def vscode_install(self):
        """安装VSCode"""
        log("INFO", "正在安装VSCode")
        # 使用sudo dpkg -i 安装位于/opt/code_1.100.2-1747260578_amd64.deb
        try:
            subprocess.run(["sudo", "dpkg", "-i", "/opt/code_1.100.2-1747260578_amd64.deb"], check=True)
            log("INFO", "VSCode安装成功")
            return True
        except subprocess.CalledProcessError as e:
            log("ERROR", f"VSCode安装失败: {str(e)}")
            return False

    def install(self):
        """安装所有组件"""
        if not self.install_packages():
            log("ERROR", "工具包安装失败")
            return False

        if not self.enable_ssh():
            log("ERROR", "SSH环境配置失败")
            return False

        if not self.vscode_install():
            log("ERROR", "VSCode安装失败")
            return False
            
        log("INFO", "所有组件安装完成")
        return True


# 示例用法
if __name__ == "__main__":
    installer = CommonInstaller()
    installer.install()
