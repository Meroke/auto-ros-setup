#!/usr/bin/env python3
import os
import sys
import subprocess
import time
import re
from logging_lib import log  # 导入日志模块

class RosSetup:
    """Class to manage ROS environment setup for Jetson devices."""

    def __init__(self):
        """Initialize system information and configuration."""
        self.ubuntu_version = subprocess.run(["lsb_release", "-rs"], capture_output=True, text=True).stdout.strip()
        self.ubuntu_codename = subprocess.run(["lsb_release", "-sc"], capture_output=True, text=True).stdout.strip()
        self.tsinghua_source_url = "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
        self.ros_version_map = {"18.04": "melodic", "20.04": "noetic"}
        self.ros_version = self.ros_version_map.get(self.ubuntu_version, "")
        os.environ["ROS_DISTRO"] = self.ros_version

    def validate_ubuntu_version(self):
        """Validate supported Ubuntu version."""
        if not self.ros_version:
            log("ERROR", f"Unsupported Ubuntu version: {self.ubuntu_version} (only 18.04/20.04 supported)")
            sys.exit(1)

    # def check_architecture(self):
    #     """Check if the system architecture is ARM64."""
    #     arch = subprocess.run(["uname", "-m"], capture_output=True, text=True).stdout.strip()
    #     if arch != "aarch64":
    #         log("ERROR", "This script is only for ARM64 architecture devices")
    #         sys.exit(1)

    def setup_tsinghua_source(self):
        """Configure Tsinghua mirror source."""
        log("INFO", f"Configuring Tsinghua mirror source (Ubuntu {self.ubuntu_codename})...")
        subprocess.run(["sudo", "cp", "/etc/apt/sources.list", "/etc/apt/sources.list.bak"], check=True)
        sources_content = f"""# Tsinghua mirror source (Ubuntu {self.ubuntu_codename.title()} for ARM)
deb {self.tsinghua_source_url} {self.ubuntu_codename} main restricted universe multiverse
deb {self.tsinghua_source_url} {self.ubuntu_codename}-updates main restricted universe multiverse
deb {self.tsinghua_source_url} {self.ubuntu_codename}-backports main restricted universe multiverse
deb {self.tsinghua_source_url} {self.ubuntu_codename}-security main restricted universe multiverse
"""
        subprocess.run(["sudo", "tee", "/etc/apt/sources.list"], input=sources_content.encode(), check=True)
        log("INFO", "Tsinghua source configuration completed")

    def check_ros_base(self):
        """检查ROS基础安装和环境配置"""
        # 检查ROS安装目录
        ros_path = f"/opt/ros/{self.ros_version}"
        if not os.path.exists(ros_path):
            log("ERROR", f"ROS安装目录不存在: {ros_path}")
            return False

        # 检查并配置bashrc
        log("INFO", "检查bash环境配置")
        bashrc_file = os.path.expanduser("~/.bashrc")
        marker = f"# ROS {self.ros_version} 配置"
        source_cmd = f"source {ros_path}/setup.bash"

        try:
            # 检查配置是否已存在
            with open(bashrc_file, "r") as f:
                content = f.read()
                if source_cmd in content:
                    log("INFO", "ROS环境配置已存在")
                    return True

            # 添加配置
            log("INFO", f"添加ROS环境配置到 {bashrc_file}")
            with open(bashrc_file, "a") as f:
                f.write(f"\n{marker}\n{source_cmd}\n")
            log("INFO", "ROS环境配置添加成功")
            return True

        except Exception as e:
            log("ERROR", f"配置.bashrc文件失败: {str(e)}")
            return False

    def get_ros_ip(self):
        """Get the preferred IP address for ROS configuration."""
        wifi_regex = r'^(wlan|wlp|wlo|wlx|ra|wifi)[0-9]+'
        loopback_regex = r'^127\.|^169\.254\.'
        target_ip = "127.0.0.1"

        ip_output = subprocess.run(["ip", "-o", "-4", "addr", "show"], capture_output=True, text=True).stdout
        ip_list = []
        for line in ip_output.splitlines():
            parts = line.split()
            if len(parts) < 4 or parts[2] != "inet":
                continue
            iface, cidr_ip = parts[1], parts[3]
            if re.match(loopback_regex, cidr_ip):
                continue
            ip = cidr_ip.split("/")[0]
            priority = 2 if re.match(wifi_regex, iface) else 1
            ip_list.append((priority, ip))
        
        ip_list.sort(key=lambda x: (-x[0], x[1]))
        if ip_list:
            target_ip = ip_list[0][1]
        return target_ip

    def setup_ros_env(self):
        """Configure single-machine ROS environment."""
        bashrc_file = os.path.expanduser("~/.bashrc")
        marker = "# ROS single-machine configuration"
        ros_ip = self.get_ros_ip()
        env_config = [
            f"export ROS_HOSTNAME={ros_ip}",
            f"export ROS_MASTER_URI=http://{ros_ip}:11311"
        ]
        log("INFO", "Configuring single-machine ROS environment...")
        with open(bashrc_file, "r") as f:
            if f"ROS_MASTER_URI=http://{ros_ip}:11311" in f.read():
                log("INFO", "[Exists] Single-machine ROS configuration unchanged")
                return
        log("INFO", f"Writing single-machine ROS config to {bashrc_file}")
        with open(bashrc_file, "a") as f:
            f.write(f"\n{marker}\n" + "\n".join(env_config) + f"\n# {marker} end\n")
        log("INFO", "[Success] Single-machine ROS environment configured:")
        for line in env_config:
            log("INFO", line)


    def check_ros_installation(self):
        """Verify ROS installation and environment."""
        log("INFO", "Checking ROS environment...")
        ros_path = f"/opt/ros/{self.ros_version}"
        if not os.path.isdir(ros_path):
            log("ERROR", f"ROS {self.ros_version} not detected, path missing: {ros_path}")
            log("WARN", "Attempting automatic ROS installation...")
            try:
                subprocess.run(["wget", "http://fishros.com/install", "-O", "fishros"], check=True)
                log("INFO", "Starting interactive installation, follow prompts...")
                subprocess.run(["bash", "fishros"], check=True)
                time.sleep(5)
                if not os.path.isdir(ros_path):
                    log("ERROR", "ROS still not detected after installation. Possible issues:")
                    log("ERROR", "1. Installation interrupted")
                    log("ERROR", "2. Incorrect system source configuration")
                    log("ERROR", "Try manual installation: curl -s https://fishros.com/install | bash")
                    sys.exit(1)
            except subprocess.CalledProcessError:
                log("ERROR", "Automatic installation failed, check network connection")
                sys.exit(1)

        log("DEBUG", f"Attempting to source environment: {ros_path}/setup.bash")
        try:
            subprocess.run(["bash", "-c", f"source {ros_path}/setup.bash && env"], check=True)
        except subprocess.CalledProcessError as e:
            log("ERROR", "Environment initialization failed, details:")
            log("ERROR", str(e))
            sys.exit(1)

        required_commands = ["rosrun", "rospack", "rosmsg"]
        for cmd in required_commands:
            if subprocess.run(["which", cmd], capture_output=True).returncode != 0:
                log("ERROR", f"Core component missing - command not found: {cmd}")
                log("WARN", f"Current installation is ros-base, consider installing: sudo apt install ros-{os.environ.get('ROS_DISTRO')}-ros-base")
                sys.exit(1)
        log("INFO", f"ROS environment verified (version: {os.environ.get('ROS_DISTRO')})")

    def setup(self):
        """Main method to control ROS setup, returns 0 on success, 1 on failure."""
        try:
            self.validate_ubuntu_version()
            # self.check_architecture()
            # log("WARN", "This operation will modify system APT source configuration")
            # log("WARN", "Original configuration backed up to /etc/apt/sources.list.bak")
            # self.setup_tsinghua_source()
            self.check_ros_base()
            self.setup_ros_env()
            log("INFO", "Applying environment configuration...")
            try:
                subprocess.run(["bash", "-c", f"source {os.path.expanduser('~/.bashrc')}"], check=True)
            except subprocess.CalledProcessError:
                log("ERROR", "Failed to load environment configuration, run manually: source ~/.bashrc")
                sys.exit(1)
            log("INFO", "Installation complete! Environment is active.")
            log("INFO", f"System info: Ubuntu {self.ubuntu_codename.title()} {self.ubuntu_version} | ROS {self.ros_version}")
            self.check_ros_installation()
            return True
        except Exception as e:
            log("ERROR", f"Setup failed: {str(e)}")
            return False

if __name__ == "__main__":
    ros_setup = RosSetup()
    sys.exit(ros_setup.setup())