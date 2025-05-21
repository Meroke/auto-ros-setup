#!/usr/bin/env python3
import sys
import os
from datetime import datetime

# 定义日志颜色（使用 ANSI 转义码）
COLORS = {
    "DEBUG": "\033[34m",  # 蓝色
    "INFO": "\033[32m",   # 绿色
    "WARN": "\033[33m",   # 黄色
    "ERROR": "\033[31m",  # 红色
    "reset": "\033[0m"
}

# 定义日志级别及其对应的整数值
LOG_LEVELS = {
    "DEBUG": 0,
    "INFO": 1,
    "WARN": 2,
    "ERROR": 3
}

# 默认日志级别，可通过环境变量 LOG_LEVEL 修改
current_level = LOG_LEVELS.get(os.environ.get("LOG_LEVEL", "DEBUG").upper(), 0)

def log(level, message):
    """
    日志输出函数
    参数:
        level (str): 日志级别 (DEBUG, INFO, WARN, ERROR)
        message (str): 日志消息
    """
    level = level.upper()
    if level not in LOG_LEVELS:
        print(f"无效日志级别: {level}", file=sys.stderr)
        return 1

    level_int = LOG_LEVELS[level]
    current_level_int = current_level

    if level_int >= current_level_int:
        timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        print(f"{COLORS[level]}[{timestamp}][{level}] {message}{COLORS['reset']}", file=sys.stderr)