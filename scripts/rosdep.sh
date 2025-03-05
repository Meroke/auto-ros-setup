#!/bin/bash
set -euo pipefail
source ./logging_lib.sh


# 定义操作目录和目标文件列表
# 如果ROS_DISTRO为noetic，则使用/usr/lib/python3/dist-packages
# 否则使用/usr/lib/python2.7/dist-packages
if [ "$ROS_DISTRO" = "noetic" ]; then
    TARGET_DIR="/usr/lib/python3/dist-packages"
else
    TARGET_DIR="/usr/lib/python2.7/dist-packages"
fi

FILES_TO_PATCH=(
    "rosdistro/__init__.py"
    "rosdep2/gbpdistro_support.py"
    "rosdep2/sources_list.py" 
    "rosdep2/rep3.py"
)

# 检查当前用户是否为Root
if [ "$(id -u)" -eq 0 ]; then
    log WARN "错误：本脚本禁止使用Root用户运行！" >&2
    exit 1
fi

# 后续正常执行流程
log INFO "当前用户权限验证通过，开始执行任务..."

#如果ROS_DISTRO为noetic，则使用python3-rosdep
if [ "$ROS_DISTRO" = "noetic" ]; then
    log INFO "安装python3-rosdep"
    sudo apt install -y python3-rosdep 
else
    log INFO "安装python-rosdep"
    sudo apt install -y python-rosdep
fi

# 创建备份目录
BACKUP_DIR="$HOME/rosdep_backup_$(date +%s)"
mkdir -p "$BACKUP_DIR"

# 执行替换操作
for rel_path in "${FILES_TO_PATCH[@]}"; do
    file_path="${TARGET_DIR}/${rel_path}"
    
    # 验证文件存在性
    if [ ! -f "$file_path" ]; then
        log ERROR "错误：未找到文件 $file_path"
        exit 1
    fi

    # 创建备份
    backup_path="${BACKUP_DIR}/$(basename $file_path)"
    sudo cp "$file_path" "$backup_path"
    log INFO "已创建备份: $backup_path"

    # 执行替换（使用|作为分隔符避免转义问题）
    sudo sed -i "s|raw.githubusercontent.com/ros/rosdistro/master|gitee.com/zhao-xuzuo/rosdistro/raw/master|g" "$file_path"
    log INFO "成功修改: $file_path"
done

# 初始化rosdep
sudo rm -f /etc/ros/rosdep/sources.list.d/20-default.list
log INFO "\n正在初始化rosdep..."
if ! sudo rosdep init; then
    log INFO "rosdep失败，请检查网络问题"
fi

# 更新rosdep数据库（最多重试3次）
MAX_RETRY=3
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRY ]; do
    if rosdep update; then
        log INFO "\n\e[32m操作成功完成！\e[0m"
        exit 0
    else
        ((RETRY_COUNT++))
        log ERROR "\n\e[33m更新失败，正在重试($RETRY_COUNT/$MAX_RETRY)...\e[0m"
        sleep 5
    fi
done

log ERROR "\n\e[31m错误：更新失败，请检查以下内容："
log ERROR "1. 确保网络连接正常"
log ERROR "2. 检查gitee镜像是否可用"
log ERROR "3. 尝试手动执行：rosdep update --include-eol-distros"
log ERROR "4. 恢复备份文件：sudo cp $BACKUP_DIR/* $TARGET_DIR/"
exit 1
