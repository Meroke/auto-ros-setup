#!/usr/bin/env python3
import os
import sys
import subprocess
import time
from logging_lib import log  # 导入日志模块

class RobotSetup:
    """Class to manage robot setup and installation processes."""
    CONFIG = {
        "base_dir": "/opt/dm_ws",
        "deps_dir": "/opt/dm_ws",
        "abseil_commit": "215105818dfde3174fe799600bb0f3cae233d0bf",
        "protobuf_version": "v3.6.1",
        "ceres_commit": "db1f5b57a0a42ea87bdb1ada25807e30d341b2ce",
        "carto_source": "/opt/dm_ws/cartographer",
        "ydlidar_sdk": "YDLidar-SDK"
    }

    def __init__(self):
        self.current_dir = os.getcwd()

    def validate_environment(self):
        """Ensure required directories exist and are writable."""
        for dir_path in [self.CONFIG["deps_dir"], self.CONFIG["base_dir"]]:
            if not os.access(dir_path, os.W_OK):
                try:
                    os.makedirs(dir_path, exist_ok=True)
                except OSError:
                    log("ERROR", f"Directory unwritable or creation failed: {dir_path}")
                    sys.exit(1)
            else:
                os.makedirs(dir_path, exist_ok=True)

    def safe_cd(self, path):
        """Safely change directory, exit on failure."""
        try:
            os.chdir(path)
        except OSError:
            log("ERROR", f"Failed to change to directory: {path}")
            sys.exit(1)

    def install_system_deps(self):
        """Install system-level dependencies."""
        log("INFO", "Installing system dependencies...")
        deps = [
            "cmake", "g++", "git", "ninja-build",
            "libboost-all-dev", "libeigen3-dev", "libatlas-base-dev", "libsuitesparse-dev",
            "libprotobuf-dev", "protobuf-compiler",
            "libgflags-dev", "libgoogle-glog-dev", "libjsoncpp-dev", "libjson-c-dev",
            "libcurl4-openssl-dev", "libcairo2-dev",
            "google-mock", "lsb-release", "stow",
            "liblua5.3-dev", "liblapack-dev", "libcxsparse3",
            "libgtest-dev", "libgstreamer1.0-dev", "libgstreamer-plugins-base1.0-dev"
        ]
        if os.environ.get("ROS_DISTRO") == "noetic":
            deps.extend(["python3-sphinx", "python3-wstool", "python3-empy", "python3-catkin-pkg-modules",
                         "python3-catkin-pkg", "python3-rospkg", "python3-catkin-tools", "python3-opencv", "libopencv-dev"])
        else:
            deps.extend(["python-sphinx", "python-wstool", "python-empy", "python-catkin-pkg-modules",
                         "python-catkin-pkg", "python-rospkg", "python-catkin-tools"])

        subprocess.run(["sudo", "apt-get", "update"], check=True)
        try:
            subprocess.run(["sudo", "apt-get", "install", "-y"] + deps, check=True)
        except subprocess.CalledProcessError:
            log("ERROR", "Dependency installation failed")
            sys.exit(1)

        subprocess.run(["sudo", "ln", "-sfv", "/usr/include/lua5.3", "/usr/include/lua"], check=True)
        subprocess.run(["sudo", "ln", "-sfv", f"/usr/lib/{os.uname().machine}-linux-gnu/liblua5.3.so", "/usr/lib/liblua.so"], check=True)
        log("INFO", "System dependencies installed")

    def clone_and_checkout(self, repo, path, commit):
        """Clone a Git repository and checkout a specific commit."""
        if not os.path.isdir(path):
            subprocess.run(["git", "clone", repo, path], check=True)
        self.safe_cd(path)
        if commit:
            subprocess.run(["git", "checkout", commit], check=True)

    def build_with_ninja(self, src_dir, *args):
        """Build a project using Ninja."""
        if not args:
            log("ERROR", "Missing CMake arguments")
            sys.exit(1)
        build_dir = os.path.join(src_dir, "build")
        source_dir, cmake_opts = args[-1], list(args[:-1])
        log("INFO", f"Source: {src_dir}, Build: {build_dir}, CMake opts: {' '.join(cmake_opts)}")
        os.makedirs(build_dir, exist_ok=True)
        self.safe_cd(build_dir)
        if not os.path.isdir(source_dir):
            log("ERROR", f"CMake source path does not exist: {source_dir}")
            sys.exit(1)
        subprocess.run(["cmake", "-G", "Ninja"] + cmake_opts + [source_dir], check=True)
        subprocess.run(["ninja"], check=True)
        subprocess.run(["sudo", "ninja", "install"], check=True)

    def install_dependency(self, name, repo, commit, *args):
        """Install a single dependency."""
        log("INFO", f"Installing {name}...")
        self.clone_and_checkout(repo, os.path.join(self.CONFIG["deps_dir"], name), commit)
        full_args = list(args) if args and args[-1].startswith("../") else list(args) + [".."]
        self.build_with_ninja(os.path.join(self.CONFIG["deps_dir"], name), *full_args)

    def setup_core_dependencies(self):
        """Install core dependencies."""
        self.install_dependency("abseil-cpp", "https://gitee.com/oscstudio/abseil-cpp.git", "",
                               "-DCMAKE_BUILD_TYPE=Release", "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "..")
        self.install_dependency("ceres-solver", "https://gitee.com/mirrors/ceres-solver.git", "",
                               "-DBUILD_TESTING=OFF", "-DBUILD_EXAMPLES=OFF", "-DCMAKE_BUILD_TYPE=Release",
                               "-DCMAKE_POSITION_INDEPENDENT_CODE=ON", "..")

    def setup_cartographer(self):
        """Install Cartographer core library."""
        log("INFO", "Installing Cartographer core library...")
        self.install_dependency("cartographer", "https://gitee.com/mirrors/cartographer.git", "master",
                               "-DCMAKE_BUILD_TYPE=Release", "..")

    def setup_ydlidar_sdk(self):
        """Configure YDLidar SDK."""
        self.install_dependency(self.CONFIG["ydlidar_sdk"], "https://github.com/YDLIDAR/YDLidar-SDK.git", "master")
        log("INFO", "Configuring YDLidar environment...")
        self.safe_cd(os.path.join(self.CONFIG["deps_dir"], self.CONFIG["ydlidar_sdk"]))
        subprocess.run(["sudo", "ldconfig"], check=True)

    def uninstall_ros_packages(self):
        """Uninstall specified ROS packages."""
        target_packages = [f"ros-{os.environ.get('ROS_DISTRO')}-cartographer-ros-msgs",
                          f"ros-{os.environ.get('ROS_DISTRO')}-cartographer"]
        for pkg in target_packages:
            result = subprocess.run(["dpkg", "-l", pkg], capture_output=True, text=True)
            if "ii  " + pkg in result.stdout:
                log("INFO", f"Uninstalling installed package: {pkg}")
                subprocess.run(["sudo", "apt-get", "remove", "--purge", "-y", pkg], check=True)
            else:
                log("INFO", f"Package not detected: {pkg}")
        subprocess.run(["sudo", "apt-get", "autoremove", "-y"], check=True)
        log("INFO", "ROS package cleanup completed")

    def fix_permissions(self):
        """Fix directory permissions."""
        current_user = os.getlogin()
        target_dir = "/opt/dm_ws"
        log("INFO", f"Fixing permissions: user={current_user}, dir={target_dir}")
        try:
            subprocess.run(["sudo", "chown", "-R", f"{current_user}:{current_user}", target_dir], check=True)
            subprocess.run(["sudo", "chmod", "-R", "755", target_dir], check=True)
            log("INFO", "Permissions fixed")
        except subprocess.CalledProcessError:
            log("ERROR", "Permission fix failed! Check if target path exists")
            sys.exit(1)

    def downgrades(self):
        """Downgrade dependencies and install additional dev libraries."""
        log("WARN", "Downgrading pulseaudio dependencies...")
        subprocess.run(["sudo", "apt-get", "install", "-y", "--allow-downgrades",
                        "libpulse-mainloop-glib0=1:13.99.1-1ubuntu3.13", "libpulse0=1:13.99.1-1ubuntu3.13",
                        "libpulsedsp=1:13.99.1-1ubuntu3.13", "pulseaudio=1:13.99.1-1ubuntu3.13",
                        "pulseaudio-module-bluetooth=1:13.99.1-1ubuntu3.13", "pulseaudio-utils=1:13.99.1-1ubuntu3.13"], check=True)
        log("WARN", "Installing additional dev libraries...")
        subprocess.run(["sudo", "apt-get", "install", "-y", "libasound2-dev", "libcaca-dev", "libpulse-dev",
                        "libsdl1.2-dev", "libsdl1.2debian", "libslang2-dev"], check=True)

    def check_and_switch_branch_nav(self):
        """Switch navigation package Git branch based on ROS_DISTRO."""
        nav_dir = os.path.join(self.CONFIG["base_dir"], "src/navigation")
        self.safe_cd(nav_dir)
        ros_distro = os.environ.get("ROS_DISTRO")
        if not ros_distro:
            log("ERROR", "ROS_DISTRO environment variable must be set")
            sys.exit(1)
        if subprocess.run(["git", "rev-parse", "--is-inside-work-tree"], capture_output=True).returncode != 0:
            log("ERROR", f"Not a Git repository: {os.getcwd()}")
            sys.exit(1)
        target_branch = f"{ros_distro}-devel"
        current_branch = subprocess.run(["git", "branch", "--show-current"], capture_output=True, text=True).stdout.strip()
        if current_branch == target_branch:
            log("INFO", f"Branch already matches: {target_branch}")
            return
        if subprocess.run(["git", "show-ref", "--quiet", f"refs/heads/{target_branch}"]).returncode == 0:
            log("INFO", f"Switching to branch: {target_branch}")
            subprocess.run(["git", "checkout", "-q", target_branch], check=True)
            log("INFO", "Switch completed")
        else:
            log("ERROR", f"Target branch does not exist: {target_branch}")
            sys.exit(1)

    def build_ros_workspace(self):
        """Build ROS workspace."""
        self.safe_cd(self.CONFIG["base_dir"])
        if os.listdir("src"):
            log("INFO", "Installing ROS dependencies...")
            subprocess.run(["sudo", "apt", "install", "-y",
                            f"ros-{os.environ.get('ROS_DISTRO')}-ackermann-msgs",
                            f"ros-{os.environ.get('ROS_DISTRO')}-joint-state-publisher",
                            f"ros-{os.environ.get('ROS_DISTRO')}-serial",
                            f"ros-{os.environ.get('ROS_DISTRO')}-tf",
                            f"ros-{os.environ.get('ROS_DISTRO')}-tf2-geometry-msgs",
                            f"ros-{os.environ.get('ROS_DISTRO')}-angles",
                            "ros-{os.environ.get('ROS_DISTRO')}-image-transport",
                            "liborocos-bfl-dev"], check=True)
            rosdep_retry, max_rosdep_retries = 0, 2
            while True:
                try:
                    subprocess.run(["rosdep", "install", "--from-paths", "src", "--ignore-src", "-y",
                                    f"--rosdistro={os.environ.get('ROS_DISTRO')}",
                                    "--skip-keys", "turtlebot_bringup kobuki_safety_controller cartographer bfl python_orocos_kdl"], check=True)
                    break
                except subprocess.CalledProcessError:
                    rosdep_retry += 1
                    if rosdep_retry >= max_rosdep_retries:
                        log("ERROR", "rosdep installation failed, downgrading dependencies...")
                        self.downgrades()
                        log("INFO", "Retrying rosdep installation...")
                        continue
                    log("WARN", f"rosdep failed, retrying ({rosdep_retry}/{max_rosdep_retries})...")
                    time.sleep(3)
            self.uninstall_ros_packages()
            log("INFO", "Building workspace (max 3 retries)...")
            retry_count, max_retries = 0, 3
            while True:
                try:
                    subprocess.run(["catkin", "build"], check=True)
                    log("INFO", "Build successful")
                    break
                except subprocess.CalledProcessError:
                    retry_count += 1
                    if retry_count >= max_retries:
                        log("ERROR", "Build failed after max retries")
                        sys.exit(1)
                    log("WARN", f"Build failed, retrying ({retry_count}/{max_retries})...")
                    time.sleep(10)
        else:
            log("WARN", "src directory empty, skipping ROS build")

    def setup_bashrc(self):
        """Configure .bashrc file."""
        bashrc_file = os.path.expanduser("~/.bashrc")
        source_cmd = f"source {self.CONFIG['deps_dir']}/devel/setup.bash"
        marker = "# Robot workspace setup"
        log("INFO", "Checking .bashrc configuration...")
        with open(bashrc_file, "r") as f:
            if source_cmd in f.read():
                log("INFO", f"Environment config already exists in {bashrc_file}")
                return
        log("INFO", f"Adding ROS workspace config to {bashrc_file}")
        with open(bashrc_file, "a") as f:
            f.write(f"\n{marker}\n{source_cmd}\n")
        with open(bashrc_file, "r") as f:
            if source_cmd not in f.read():
                log("ERROR", f"Failed to write to {bashrc_file}")
                sys.exit(1)
        log("INFO", f"Added environment config: {source_cmd}")

    def setup(self):
        """Main method to control installation process, returns 0 on success, 1 on failure."""
        try:
            self.validate_environment()
            self.install_system_deps()
            self.setup_core_dependencies()
            self.setup_cartographer()
            # self.setup_ydlidar_sdk()  # Commented out as in original
            self.fix_permissions()
            self.build_ros_workspace()
            self.setup_bashrc()
            subprocess.run(["sudo", "ldconfig"], check=True)
            log("INFO", f"Installation complete!\nWorkspace path: {self.CONFIG['base_dir']}")
            return 0
        except Exception as e:
            log("ERROR", f"Execution failed: {str(e)}")
            return 1

if __name__ == "__main__":
    setup = RobotSetup()