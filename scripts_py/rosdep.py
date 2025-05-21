#!/usr/bin/env python3
import os
import sys
import subprocess
import time
from logging_lib import log  # 导入日志模块

class RosdepSetup:
    """Class to manage rosdep configuration and installation."""

    def __init__(self):
        """Initialize configuration based on ROS_DISTRO."""
        self.ros_distro = os.environ.get("ROS_DISTRO", "")
        self.target_dir = "/usr/lib/python3/dist-packages" if self.ros_distro == "noetic" else "/usr/lib/python2.7/dist-packages"
        self.files_to_patch = [
            "rosdistro/__init__.py",
            "rosdep2/gbpdistro_support.py",
            "rosdep2/sources_list.py",
            "rosdep2/rep3.py"
        ]

    def check_root(self):
        """Check if running as root, exit if true."""
        if os.geteuid() == 0:
            log("WARN", "Error: This script must not run as root!")
            sys.exit(1)
        log("INFO", "User permission check passed, starting tasks...")

    def install_rosdep(self):
        """Install appropriate rosdep package based on ROS_DISTRO."""
        package = "python3-rosdep" if self.ros_distro == "noetic" else "python-rosdep"
        log("INFO", f"Installing {package}")
        subprocess.run(["sudo", "apt", "install", "-y", package], check=True)

    def create_backup(self):
        """Create backup directory for modified files."""
        backup_dir = f"{os.path.expanduser('~')}/rosdep_backup_{int(time.time())}"
        os.makedirs(backup_dir, exist_ok=True)
        return backup_dir

    def patch_files(self, backup_dir):
        """Patch files by replacing GitHub URLs with Gitee URLs."""
        for rel_path in self.files_to_patch:
            file_path = os.path.join(self.target_dir, rel_path)
            if not os.path.isfile(file_path):
                log("ERROR", f"Error: File not found: {file_path}")
                sys.exit(1)

            backup_path = os.path.join(backup_dir, os.path.basename(file_path))
            subprocess.run(["sudo", "cp", file_path, backup_path], check=True)
            log("INFO", f"Backup created: {backup_path}")

            try:
                with open(file_path, "r") as f:
                    content = f.read()
                content = content.replace(
                    "raw.githubusercontent.com/ros/rosdistro/master",
                    "gitee.com/zhao-xuzuo/rosdistro/raw/master"
                )
                subprocess.run(["sudo", "tee", file_path], input=content.encode(), check=True)
                log("INFO", f"Successfully patched: {file_path}")
            except Exception as e:
                log("ERROR", f"Failed to patch file {file_path}: {str(e)}")
                sys.exit(1)

    def initialize_rosdep(self):
        """Initialize rosdep, removing default sources list if present."""
        default_list = "/etc/ros/rosdep/sources.list.d/20-default.list"
        if os.path.exists(default_list):
            subprocess.run(["sudo", "rm", "-f", default_list], check=True)
        log("INFO", "\nInitializing rosdep...")
        try:
            subprocess.run(["sudo", "rosdep", "init"], check=True)
        except subprocess.CalledProcessError:
            log("INFO", "rosdep initialization failed, check network issues")

    def update_rosdep(self, backup_dir):
        """Update rosdep database with retries."""
        max_retry, retry_count = 3, 0
        while retry_count < max_retry:
            try:
                subprocess.run(["rosdep", "update"], check=True)
                log("INFO", "\n\033[32mOperation completed successfully!\033[0m")
                return True
            except subprocess.CalledProcessError:
                retry_count += 1
                log("ERROR", f"\n\033[33mUpdate failed, retrying ({retry_count}/{max_retry})...\033[0m")
                time.sleep(5)
        
        log("ERROR", "\n\033[31mError: Update failed, please check the following:")
        log("ERROR", "1. Ensure network connectivity")
        log("ERROR", "2. Verify Gitee mirror availability")
        log("ERROR", "3. Try manually: rosdep update --include-eol-distros")
        log("ERROR", f"4. Restore backups: sudo cp {backup_dir}/* {self.target_dir}/")
        return False

    def setup(self):
        """Main method to control rosdep setup, returns 0 on success, 1 on failure."""
        try:
            self.check_root()
            self.install_rosdep()
            backup_dir = self.create_backup()
            self.        (backup_dir)
            self.initialize_rosdep()
            success = self.update_rosdep(backup_dir)
            return 0 if success else 1
        except Exception as e:
            log("ERROR", f"Setup failed: {str(e)}")
            return 1

if __name__ == "__main__":
    rosdep = RosdepSetup()
    sys.exit(rosdep.setup())