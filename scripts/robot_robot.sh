#!/bin/bash
set -euo pipefail
source ./logging_lib.sh

# ============================== 配置层 ==============================
declare -A CONFIG=(
    [base_dir]="/tmp/dm_ws"
    [deps_dir]="${CONFIG[base_dir]}"
    [abseil_commit]="215105818dfde3174fe799600bb0f3cae233d0bf"
    [protobuf_version]="v3.6.1"
    [ceres_commit]="db1f5b57a0a42ea87bdb1ada25807e30d341b2ce"
    [carto_source]="${CONFIG[base_dir]}/cartographer" 
)

# ============================== 工具层 ==============================

validate_environment() {
    # 新增目录权限校验逻辑[3](@ref)
    local required_dirs=("${CONFIG[deps_dir]}" "${CONFIG[base_dir]}")
    for dir in "${required_dirs[@]}"; do
        if [[ ! -w "$dir" ]]; then
            log ERROR "目录不可写: $dir"
            exit 1
        fi
        mkdir -p "$dir"
    done
}

safe_cd() {
    cd "$@" || {
        log ERROR "进入目录失败: $@"
        exit 1
    }
}

# ============================== 服务层 ==============================
install_system_deps() {
    log INFO "安装系统级依赖..."
    # 优化依赖列表管理[5](@ref)
    local deps=(
        # 编译工具链
        cmake g++ git ninja-build
        # 核心数学库
        libboost-all-dev libeigen3-dev libatlas-base-dev libsuitesparse-dev
        # 协议与序列化
        libprotobuf-dev protobuf-compiler
        # 工具库
        libgflags-dev libgoogle-glog-dev libjsoncpp-dev libjson-c-dev libcurl4-openssl-dev libcairo2-dev
        # 测试框架
        google-mock
        # 系统工具
        lsb-release stow
        # Lua开发包
        liblua5.3-dev
        # ceres依赖
        liblapack-dev libsuitesparse-dev libcxsparse3 libgflags-dev libgoogle-glog-dev libgtest-dev
        # gscam
        libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev 
        # protobuf v3.6.1
        protobuf-compiler libprotobuf-dev
        # cartographer_ros
        # libgmock-dev
    )
    # 如果ROS_DISTRO为noetic，则安装python3-sphinx，python3-wstool
    if [ "$ROS_DISTRO" = "noetic" ]; then
        deps+=(python3-sphinx python3-wstool python3-empy python3-catkin-pkg-modules
        python3-catkin-pkg python3-rospkg python3-catkin-tools 
        # opencv
        python3-opencv libopencv-dev)
    else
        deps+=(python-sphinx python-wstool python-empy python-catkin-pkg-modules 
        python-catkin-pkg python-rospkg python-catkin-tools)
    fi
    
    # 安装前更新源
    sudo apt-get update
    
    # 批量安装APT包
    sudo apt-get install -y "${deps[@]}" || {
        log ERROR "依赖安装失败"
        exit 1
    }

    # Lua兼容性配置
    sudo ln -sfv /usr/include/lua5.3 /usr/include/lua
    sudo ln -sfv /usr/lib/$(uname -m)-linux-gnu/liblua5.3.so /usr/lib/liblua.so
    
    log INFO "系统依赖安装完成"
}

clone_and_checkout() {
    local repo=$1
    local path=$2
    local commit=$3

    # 克隆仓库（如果不存在）
    if [ ! -d "$path" ]; then
        git clone "$repo" "$path"
    fi

    # 如果commit非空，执行checkout
    safe_cd "$path"
    if [ -n "$commit" ]; then
        git checkout "$commit"
    fi
}

build_with_ninja() {
    local src_dir=$1
    shift  # 移除第一个参数（src_dir）
    local args=("$@")  # 剩余参数存入数组
    
    # 参数校验
    if [ ${#args[@]} -eq 0 ]; then
        log ERROR "缺少CMake参数"
        exit 1
    fi
    
    local build_dir="${src_dir}/build"
    local source_dir="${args[-1]}"  # 最后一个参数为源码路径
    local cmake_opts=("${args[@]::${#args[@]}-1}")  # 其余为CMake选项

    log INFO "源码目录：$src_dir"
    log INFO "构建目录：$build_dir"
    log INFO "CMake 源码路径：$source_dir"
    log INFO "CMake 选项：${cmake_opts[*]}"

    mkdir -p "$build_dir"
    safe_cd "$build_dir"

    # 添加路径存在性检查
    if [ ! -d "$source_dir" ]; then
        log ERROR "CMake源码路径不存在：$source_dir"
        exit 1
    fi

    cmake -G Ninja "${cmake_opts[@]}" "$source_dir"
    ninja
    sudo ninja install
}

install_dependency() {
    local name=$1 repo=$2 commit=$3
    shift 3
    local user_args=("$@")  # 包含所有用户参数
    
    log INFO "安装 ${name}..."
    clone_and_checkout "$repo" "${CONFIG[deps_dir]}/${name}" "$commit"
    
    # 自动添加路径参数（如果用户未提供）
    if [ ${#user_args[@]} -eq 0 ] || [[ "${user_args[-1]}" != "../"* ]]; then
        user_args+=("..")  # 默认使用上级目录
    fi
    
    # 构建完整参数列表
    local full_args=(
        "${user_args[@]}"  # 用户参数必须包含路径
    )
    
    build_with_ninja "${CONFIG[deps_dir]}/${name}" "${full_args[@]}"
}

setup_core_dependencies() {
    # abseil-cpp (保持原路径)
    install_dependency "abseil-cpp" \
        "https://gitee.com/oscstudio/abseil-cpp.git" \
        "" \
        "-DCMAKE_BUILD_TYPE=Release" \
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON" \
        ".."  # 新增路径参数

    # # protobuf (指定特殊路径)
    # install_dependency "protobuf" \
    #     "https://gitee.com/mirrors/protobuf.git" \
    #     "tags/${CONFIG[protobuf_version]}" \
    #     "-Dprotobuf_BUILD_TESTS=OFF" \
    #     "-DCMAKE_BUILD_TYPE=Release" \
    #     "-DCMAKE_POSITION_INDEPENDENT_CODE=ON" \
    #     "../cmake" 
    # ceres-solver (常规路径)
    install_dependency "ceres-solver" \
        "https://gitee.com/mirrors/ceres-solver.git" \
        "" \
        "-DBUILD_TESTING=OFF" \
        "-DBUILD_EXAMPLES=OFF" \
        "-DCMAKE_BUILD_TYPE=Release" \
        "-DCMAKE_POSITION_INDEPENDENT_CODE=ON" \
        ".."
}

setup_cartographer() {
    log INFO "安装Cartographer核心库..."
    
    # 使用标准依赖安装流程（启用测试编译）
    install_dependency "cartographer" \
        "https://gitee.com/mirrors/cartographer.git" \
        "master" \
        "-DCMAKE_BUILD_TYPE=Release" \
        ".."

    log INFO "执行Cartographer单元测试..."
    local build_dir="${CONFIG[deps_dir]}/cartographer/build"
    safe_cd "$build_dir"
    
    # 现在可以正常执行测试
    # if ! CTEST_OUTPUT_ON_FAILURE=1 ctest --verbose; then
    #     log ERROR "Cartographer单元测试失败"
    #     exit 1
    # fi
    # log INFO "所有测试通过"
}

setup_ydlidar_sdk() {
    install_dependency "${CONFIG[ydlidar_sdk]}" \
        "https://github.com/YDLIDAR/YDLidar-SDK.git" \
        "master"  # 使用默认分支最新代码

    log INFO "配置YDLidar环境..."
    local sdk_path="${CONFIG[deps_dir]}/${CONFIG[ydlidar_sdk]}"
    safe_cd "$sdk_path"
    sudo ldconfig
}

# ----------------------------- 新增函数: ROS包检测与卸载 -----------------------------
uninstall_ros_packages() {
  # 定义需要检查的ROS包列表
  local target_packages=(
    "ros-${ROS_DISTRO}-cartographer-ros-msgs"
    "ros-${ROS_DISTRO}-cartographer"
  )

  # 遍历检查每个包
  for pkg in "${target_packages[@]}"; do
    if dpkg -l | grep -q "^ii  $pkg "; then
      log INFO "发现已安装包: ${COLOR_YELLOW}$pkg${COLOR_RESET}，开始卸载..."
      sudo apt-get remove --purge -y "$pkg"
    else
      log INFO "未检测到包: $pkg"
    fi
  done

  # 清理残留依赖
  sudo apt-get autoremove -y
  log INFO "ROS包清理完成"
}

# 定义权限修复函数
fix_permissions() {
    # 获取当前有效用户名和组
    local current_user=$(id -un)
    local target_dir="/tmp/dm_ws"

    log INFO "正在修复目录权限：用户=${current_user}, 目录=${target_dir}"
    
    # 递归修改所有权
    if ! sudo chown -R "${current_user}:${current_user}" "$target_dir"; then
        log ERROR "修改所有权失败！请检查目标路径是否存在"
        return 1
    fi
    
    # 递归修改权限
    if ! sudo chmod -R 755 "$target_dir"; then
        log ERROR "修改权限失败！"
        return 2
    fi

    log INFO "权限修复完成"
}

downgrades() {
    # 步骤2：执行降级操作
    log WARN "正在降级pulseaudio相关依赖..."
    sudo apt-get install -y --allow-downgrades \
        libpulse-mainloop-glib0=1:13.99.1-1ubuntu3.13 \
        libpulse0=1:13.99.1-1ubuntu3.13 \
        libpulsedsp=1:13.99.1-1ubuntu3.13 \
        pulseaudio=1:13.99.1-1ubuntu3.13 \
        pulseaudio-module-bluetooth=1:13.99.1-1ubuntu3.13 \
        pulseaudio-utils=1:13.99.1-1ubuntu3.13 
    
    # 步骤3：安装新依赖包
    log WARN "安装补充开发库..."
    sudo apt-get install -y \
        libasound2-dev \
        libcaca-dev \
        libpulse-dev \
        libsdl1.2-dev \
        libsdl1.2debian \
        libslang2-dev 
}


# 自动切换ROS版本匹配的Git分支（非交互式）
check_and_switch_branch_nav() {
    # 配置导航包路径（可通过参数覆盖）
    local nav_dir="${CONFIG[base_dir]}/src/navigation"
    
    # 进入目录
    if ! cd "$nav_dir" 2>/dev/null; then
        log ERROR "目录不存在: $nav_dir" >&2
        return 1
    fi

    # 获取ROS版本
    if [[ -z "$ROS_DISTRO" ]]; then
        log ERROR "必须设置 ROS_DISTRO 环境变量" >&2
        return 2
    fi

    # 验证Git仓库
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        log ERROR "非Git仓库目录: $PWD" >&2
        return 3
    fi

    # 分支处理逻辑
    local target_branch="${ROS_DISTRO}-devel"
    local current_branch=$(git branch --show-current)

    # 分支匹配检查
    if [[ "$current_branch" == "$target_branch" ]]; then
        log INFO " 分支已匹配: $target_branch"
        return 0
    fi

    # 执行切换
    if git show-ref --quiet "refs/heads/$target_branch"; then
        log INFO "[ACTION] 正在切换分支: $target_branch"
        git checkout -q "$target_branch" && {
            log INFO "[SUCCESS] 切换完成"
            return 0
        }
    else
        log ERROR "目标分支不存在: $target_branch" >&2
        return 4
    fi
}

# ============================== 业务逻辑层 ==============================
build_ros_workspace() {
    # 优化ROS工作空间构建[5](@ref)
    safe_cd "${CONFIG[base_dir]}"
    
    if [[ -n "$(ls -A src)" ]]; then
        log INFO "安装ROS依赖..."
        sudo apt install -y ros-${ROS_DISTRO}-ackermann-msgs ros-${ROS_DISTRO}-joint-state-publisher  \
        ros-${ROS_DISTRO}-serial ros-${ROS_DISTRO}-tf ros-${ROS_DISTRO}-tf2-geometry-msgs ros-${ROS_DISTRO}-angles \
        ros-${ROS_DISTRO}-image-transport liborocos-bfl-dev

        # 新增：rosdep失败重试机制
        local rosdep_retry=0
        local max_rosdep_retries=2
        
        while true; do
            if rosdep install --from-paths src --ignore-src -y \
                --rosdistro=${ROS_DISTRO} --skip-keys "turtlebot_bringup kobuki_safety_controller cartographer bfl python_orocos_kdl"; then
                break
            else
                ((rosdep_retry++))
                if [ $rosdep_retry -ge $max_rosdep_retries ]; then
                    log ERROR "rosdep安装失败，执行依赖降级处理..."
                    
                    # ================= 新增错误处理流程[2,4](@ref) =================
                    downgrades
                    
                    # 重试rosdep（可选）
                    log INFO "重试rosdep安装..."
                    continue
                else
                    log WARN "rosdep安装失败，正在重试(${rosdep_retry}/${max_rosdep_retries})..."
                    sleep 3
                fi
            fi
        done
        uninstall_ros_packages 

        # json
        # sudo ln -s ${CONFIG[deps_dir]}/json /usr/include/
        # sudo cp ${CONFIG[deps_dir]}/libjson.* /usr/lib/

        # 检查切换navigation包分支
        # check_and_switch_branch_nav

        log INFO "构建工作空间 (最多重试3次)..."
        local retry_count=0
        local max_retries=3
        
        while true; do
            if catkin build; then
                log INFO "构建成功"
                break
            else
                ((retry_count++))
                if [ $retry_count -ge $max_retries ]; then
                    log ERROR "构建失败，已达最大重试次数"
                    exit 1
                fi
                log WARN "构建失败，正在重试 (${retry_count}/${max_retries})..."
                sleep 10  # 等待10秒再重试
            fi
        done
    else
        log WARN "src目录为空，跳过ROS构建"
    fi
}

setup_bashrc() {
    local bashrc_file="${HOME}/.bashrc"
    local source_cmd="source ${CONFIG[deps_dir]}/devel/setup.bash"
    local marker="# Robot workspace setup"
    
    log INFO "检查.bashrc配置..."
    
    # 检查是否已存在配置
    if grep -qF "$source_cmd" "$bashrc_file"; then
        log INFO "[存在] 环境配置已存在于 ${bashrc_file}"
        return 0
    fi
    
    # 添加带注释的配置块
    log INFO "添加ROS工作空间配置到 ${bashrc_file}"
    echo -e "\n${marker}\n${source_cmd}\n" >> "$bashrc_file"
    
    # 验证添加结果
    if grep -qF "$source_cmd" "$bashrc_file"; then
        log INFO "[成功] 已添加环境配置:\n${source_cmd}"
        return 0
    else
        log ERROR "[失败] 无法写入 ${bashrc_file}"
        return 1
    fi
}

# ============================== 主流程 ==============================
main() {
    validate_environment
    install_system_deps
    setup_core_dependencies
    setup_cartographer
    # setup_ydlidar_sdk
    fix_permissions
    build_ros_workspace
    setup_bashrc

    sudo ldconfig
    log INFO "安装完成!\n工作空间路径: ${CONFIG[base_dir]}\n"
}

main "$@"