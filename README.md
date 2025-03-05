# AutoRosSetup

### 介绍
AutoRosSetup 是一个专注于ROS（Robot Operating System）自动配置的开源项目，简化机器人开发环境搭建过程，提高开发者效率。

### 简单流程:

1. 执行步骤一 格式化sd卡
2. 运行可执行文件`robot_installer.run`

![image.png](attachment:6d92639f-4c34-46ae-874a-4a902ab37ab6:dbcca6cf-2c3e-4810-8791-7d9b3e49aa44.png)

### 执行脚本前，需要准备：

1. 格式化成ext4格式的SD卡
2. 卡内要存好robot_robot项目文件夹。
    - 同步文件指令：
    
    `rsync -av --exclude='build' --exclude='devel' /mnt/sdcard/robot_robot/ /mnt/tmp/robot_robot`
    
3. 在jetson nano主目录下，有scripts以下脚本文件

脚本文件：
```
scripts
├── install_robot.sh  启动项；挂载sd卡
├── logging_lib.sh    日志输出配置
├── robot_robot.sh    安装项目依赖并编译
├── ros.sh            安装ros-base
├── rosdep.sh         配置rosdep
└── uninstall_ros.sh  卸载ros和build, devel
```

项目文件夹：
```
robot_robot/
├── build
├── cartographer_lib  cartographer 依赖和源码
├── cfg               配置文件
├── CMakeFiles      
├── devel 
├── logs
├── src               项目源码
└── YDLidar-SDK       雷达依赖
```

`注意：针对RK3588鲁班猫板子的网络连接，设置静态ip时，必须添加DNS 8.8.8.8，否则无法上网。`

### 一、格式化sd卡

格式化SD卡为ext4格式：

要卸载分区，而不是整个sd卡，因此是sdb1，而不是sdb

```bash
sudo umount /dev/sdb1
```

```bash
zhangjj@ubuntu:~$ sudo fdisk /dev/sdb

Welcome to fdisk (util-linux 2.34).
Changes will remain in memory only, until you decide to write them.
Be careful before using the write command.

# 删除分区
Command (m for help): d
Selected partition 1
Partition 1 has been deleted.

# 新建分区
Command (m for help): n
Partition type
   p   primary (0 primary, 0 extended, 4 free)
   e   extended (container for logical partitions)
Select (default p): p
Partition number (1-4, default 1): 
First sector (2048-122138623, default 2048): 
Last sector, +/-sectors or +/-size{K,M,G,T,P} (2048-122138623, default 122138623): 

Created a new partition 1 of type 'Linux' and of size 58.2 GiB.

# 保存退出
Command (m for help): w
The partition table has been altered.
Calling ioctl() to re-read partition table.
Syncing disks.
```

格式化sd卡：

```bash
sudo mkfs.ext4 -L "SD_CARD" /dev/sdb1
```

*注意：接下去的步骤都是脚本执行，不需要手动输入指令，可以根据下文查看流程。*

### 二、挂载sd卡，安装ros-base

 [NVIDIA官方指导手册](https://developer.nvidia.com/embedded/learn/get-started-jetson-nano-devkit#write)

[install_robot.sh 总脚本：挂载SD卡，检测ROS是否安装。](https://www.notion.so/install_robot-sh-SD-ROS-1a84fcbc43a080e998e9ff4d9fa42477?pvs=21)

[[ros.sh](http://ros.sh) 自动安装ros,更换软件源](https://www.notion.so/ros-sh-ros-1ac4fcbc43a080528bdafe07be668bed?pvs=21)

流程：

1. **初始化配置** - 设置错误处理、定义挂载点和执行器参数
2. **SD卡检测与挂载** - 动态检测SD卡设备、创建挂载目录、执行安全挂载
3. **ROS环境配置** - 检查ROS安装、尝试自动安装、验证环境变量
4. **设备规则配置** - 创建udev规则、配置设备符号链接、重载服务
5. **主要组件安装**
    1. 执行ros.sh - 配置ROS源和单机环境
    2. 执行rosdep.sh - 更新依赖数据库
    3. 执行robot_robot.sh - 构建核心库和工作空间
6. **系统持久化** - 配置fstab实现SD卡自动挂载
7. **环境验证** - 确保所有组件正确安装、输出完成提示

核心说明：

- 挂载sd卡

```bash
# 挂载sd卡/dev/mmcblk1p1 到 /mnt/sdcard
sudo mount -t ext4 /dev/mmcblk1p1 /mnt/sdcard
# 卸载
sudo umount /mnt/sdcard
```

- **设备规则配置：**

新建/etc/udev/rules.d/robot.rules，将以下内容写入

```bash
# jetson nano (ubutu18.01)
KERNELS=="1-2.2:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="wheeltec_controller"
KERNELS=="1-2.1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidar"
KERNELS=="1-2.3:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidarGS2"

# RK3588 (ubuntu20.04)
KERNELS=="2-1.1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="wheeltec_controller"
KERNELS=="3-1:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidar"
KERNELS=="2-1.2:1.0", MODE:="0777", GROUP:="dialout", SYMLINK+="ydlidarGS2"
```

继续执行以下指令，让规则生效

```bash
sudo service udev reload
sudo service udev restart
```

![image.png](attachment:a152f35c-5450-4cb3-9d2c-9c6c17b29625:image.png)

![image.png](attachment:cfefed79-8d18-4d9c-8fcd-b2ce39f5b514:image.png)

                        jetson nano 串口(开头都是1-2.)                                              rk3588 串口   

### 三、配置rosdep

[[rosdep.sh](http://rosdep.sh) 配置rosdep 脚本](https://www.notion.so/rosdep-sh-rosdep-1a84fcbc43a080609ff2f4e3b0d15265?pvs=21)

流程：

1. **安全检查** - 验证非Root用户执行，防止权限问题
2. **依赖安装** - 自动安装python-rosdep工具包
3. **备份创建** - 生成带时间戳的备份目录，保存原始文件
4. **文件修补** - 替换4个核心文件中的URL，从GitHub转向Gitee镜像
    1. rosdistro/**init**.py
    2. rosdep2/gbpdistro_support.py
    3. rosdep2/sources_list.py
    4. rosdep2/rep3.py
5. **rosdep初始化** - 删除已有配置，重新执行rosdep init
6. **数据库更新** - 执行rosdep update并实现自动重试机制
7. **故障处理** - 失败时提供详细诊断步骤和恢复方法

核心说明：

- rosdep更换gitee数据源

rosdep的源是github源，更新容易失败，需要进行换成国内源：

首先到/usr/lib/python2.7/dist-packages里寻找

```bash
./rosdistro/**init**.py
./rosdep2/gbpdistro_support.py
./rosdep2/sources_list.py
./rosdep2/rep3.py
```

然后在每个文件内搜索

`raw.githubusercontent.com/ros/rosdistro/master`

将其替换成`gitee.com/zhao-xuzuo/rosdistro/raw/master`。

然后执行

```bash
sudo rosdep init
rosdep update
```

### 四、编译robot_robot项目

[robot_robot.sh项目编译 脚本](https://www.notion.so/robot_robot-sh-1a84fcbc43a0809185f0e55556e909c3?pvs=21)

流程：

1. 环境准备 - 验证目录权限、创建必要目录
2. 系统依赖安装 - 安装编译工具、库等
3. 核心依赖构建 - 下载并编译abseil、protobuf、ceres等
4. Cartographer安装 - 构建并测试Cartographer
5. YDLidar SDK安装
6. ROS工作空间构建 - 处理依赖并编译工作空间
7.  环境配置 - 更新bashrc

核心说明：

- jetson nano 的特殊编译选项

对于cartographer的依赖项（abseil、protobuf、ceres），

编译时必须添加选项  `"-DCMAKE_POSITION_INDEPENDENT_CODE=ON”`，也就是添加PIC。

例如protobuf库的编译：

**静态库 `libprotobuf.a` 在编译时未启用位置无关代码（Position Independent Code, PIC）**，导致其无法被链接到共享库（`.so`）中。具体表现为：

1. **架构相关**：目标平台是 **AArch64**（如树莓派、Jetson等），该架构对共享库的代码重定位有严格限制。
2. **PIC缺失**：Protobuf 的静态库在编译时未添加 `fPIC` 选项，导致生成的目标文件（`.o`）无法用于构建共享库。
3. **混合链接**：项目 `cartographer_rviz` 尝试将非 PIC 的静态库 `libprotobuf.a` 链接到动态库（`.so`）中，触发重定位错误。

---

### sdk manager刷机注意事项

1. 跳冒插在从右往左数的第二、三引脚上。
2. 使用sdk manager的本地系统必须是ubuntu18.04，如果≥ubuntu20.04， 则无法烧录jetpack 4.6.4对应ubuntu18.04，也是jetson nano支持的最高版本。
3. sdk manager登录可能需要开启vpn代理，同时必须配置firefox的代理地址
4. sdk manager会先下载资源到本地系统， 确保虚拟机有32G以上的空余空间，否则无法下载。
    
    [刷机后，添加tf卡扩容](https://www.notion.so/tf-1a94fcbc43a080319ecaf925e5be59f7?pvs=21)
    

### Makeself打包指令

```bash
makeself ./scripts robot_installer.run "Robot Installation Package" ./install_robot.sh
```