#!/bin/bash

# 停止所有ROS相关进程
rosnode kill -a 2>/dev/null
killall -9 rosmaster 2>/dev/null

# 卸载所有ROS包及依赖
sudo apt-get purge ros-* -y
sudo apt-get autoremove --purge -y

# 清理残留配置
sudo rm -rf /etc/ros /opt/ros
rm -rf ~/.ros

# 删除APT源
sudo rm /etc/apt/sources.list.d/ros*.list

# 更新包列表
sudo apt update

# 指定目标目录
TARGET_DIR="/mnt/sdcard/robot_robot"

# 检查目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo "错误：工作空间 $TARGET_DIR 不存在！"
    exit 1
fi

# 列出所有待删除的目录
echo "警告：即将递归删除以下目录及其所有子内容："
find "$TARGET_DIR" -type d \( -name "build" -o -name "devel" \) -print

# 用户二次确认
read -p "确认删除？(y/n): " confirm
case "$confirm" in
    [yY])
        echo "正在执行删除操作..."
        find "$TARGET_DIR" -type d \( -name "build" -o -name "devel" \) -exec rm -rf {} +
        echo "已删除所有 build 和 devel 目录。"
        ;;
    [nN])
        echo "已取消删除操作。"
        exit 0
        ;;
    *)
        echo "输入错误，操作已中止。"
        exit 1
        ;;
esac