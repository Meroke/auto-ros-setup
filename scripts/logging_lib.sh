#!/bin/bash
# 声明全局关联数组（需Bash 4.0+）
declare -A COLORS=(
    [DEBUG]='\033[34m'    # 蓝色
    [INFO]='\033[32m'     # 绿色
    [WARN]='\033[33m'     # 黄色
    [ERROR]='\033[31m'    # 红色
    [reset]='\033[0m'
)
declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

# 可被外部修改的日志级别（默认DEBUG）
export current_level=${LOG_LEVEL:-DEBUG}

# 日志函数定义
log() {
    local level=${1^^}
    [[ -v LOG_LEVELS[$level] ]] || {
        echo "无效日志级别: $level" >&2
        return 1
    }
    # 作用域穿透处理[6,8](@ref)
    local message="${*:2}" timestamp=$(date +"%Y-%m-%d %T")
    local level_int=${LOG_LEVELS[$level]} 
    local current_level_int=${LOG_LEVELS[${current_level^^}]}

    if (( level_int >= current_level_int )); then
        echo -e "${COLORS[$level]}[${timestamp}][${level^^}] ${message}${COLORS[reset]}" >&2
    fi
}