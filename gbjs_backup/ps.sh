#!/bin/bash

# ps.sh - 智能检测进程是否运行（多方法 fallback）

usage() {
    echo "用法: $0 <进程名>"
    echo "示例: $0 nginx"
    exit 1
}

# 参数检查
if [ $# -ne 1 ]; then
    usage
fi

PROCESS_NAME=$1

# === 方法1: pgrep + ps 避免僵尸进程识别会存活===
if command -v pgrep > /dev/null 2>&1 && command -v ps > /dev/null 2>&1; then
    # 获取所有匹配该名称的 PID
    if PIDS=$(pgrep -x "$PROCESS_NAME"); then
        VALID_PIDS=""
        
        # 遍历每个 PID，检查其状态
        for PID in $PIDS; do
            # 获取进程状态 (state)，Z 代表 Zombie (defunct)
            STATE=$(ps -o state= -p "$PID" 2>/dev/null)
            
            # 如果状态不是 Z，则视为有效运行进程
            if [ "$STATE" != "Z" ]; then
                # 累加有效 PID (利用 shell 单词分割自动去除首尾空格)
                VALID_PIDS="$VALID_PIDS $PID"
            fi
        done

        # 去除可能的前导空格并检查是否有有效进程
        VALID_PIDS=$(echo $VALID_PIDS)

        if [ -n "$VALID_PIDS" ]; then
            echo "✅ 进程 '$PROCESS_NAME' 正在运行 (PID: $VALID_PIDS) [方法：pgrep +  ps状态过滤]"
            exit 0
        else
            # 如果全是僵尸进程，这里可以选择继续向下执行或报错
            echo "⚠️ 发现进程 '$PROCESS_NAME' 但均为僵尸进程 (defunct)"
            exit 1
        fi
    fi
fi


# === 方法2: pidof（适合二进制服务）(其判断未运行不准，所以不能全依赖它)===
if command -v pidof > /dev/null 2>&1; then
    PIDS=$(pidof "$PROCESS_NAME")
    if [ -n "$PIDS" ]; then
        echo "✅ 进程 '$PROCESS_NAME' 正在运行 (PID: $PIDS) [方法: pidof]"
        exit 0
    fi
fi

# === 方法3: ps + grep（通用，但注意避免匹配自身）===
# 注意：这里用 [p]attern 避免 grep 匹配到自己
if command -v ps > /dev/null 2>&1 && command -v wc > /dev/null 2>&1; then
    first=$(printf '%s\n' "$PROCESS_NAME" | cut -c 1)
    rest=$(printf '%s\n' "$PROCESS_NAME" | cut -c 2-)
    GREP_EXPR="[$first]$rest"
    echo "$GREP_EXPR"
    MATCH_COUNT=$(ps aux | grep "$GREP_EXPR" |grep -v ' -s --'|wc -l)
    if [ "$MATCH_COUNT" -gt 0 ]; then
        
        echo "✅ 进程 '$PROCESS_NAME' 正在运行，共匹配到 $MATCH_COUNT 行"
        exit 0
    else
        echo "❌ 进程 '$PROCESS_NAME' 未运行"
        exit 1
    fi
fi

# === 方法4: 遍历 /proc/<PID>/comm（底层 fallback）===
FOUND=0
for proc_dir in /proc/[0-9]*; do
    [ ! -d "$proc_dir" ] && continue
    pid=$(basename "$proc_dir")

    comm_file="$proc_dir/comm"
    if [ -r "$comm_file" ]; then
        comm=$(cat "$comm_file" 2>/dev/null | tr -d '\n')
        if [ "$comm" = "$PROCESS_NAME" ]; then
            echo "✅ 进程 '$PROCESS_NAME' 正在运行 (PID: $pid) [方法: /proc/comm]"
            FOUND=1
        fi
    fi
done

if [ $FOUND -eq 1 ]; then
    exit 0
fi

# === 方法5: 检查 /proc/<PID>/cmdline（兼容脚本、解释器）===
for proc_dir in /proc/[0-9]*; do
    [ ! -d "$proc_dir" ] && continue
    pid=$(basename "$proc_dir")

    # 排除自身进程和父进程
    if [ "$pid" = "$$" ] || [ "$pid" = "$PPID" ]; then
        continue
    fi

    status_file="$proc_dir/status"
    cmdline_file="$proc_dir/cmdline"
    
    if [ -r "$status_file" ]; then
        proc_name=$(grep -E "^Name:" "$status_file" | cut -f2)
        
        # 方法1：检查进程名（最可靠）
        if [ "$proc_name" = "$PROCESS_NAME" ]; then
            echo "✅ 进程 '$PROCESS_NAME' 正在运行 (PID: $pid) [方法: 进程名匹配]"
            exit 0
        fi
        
        # 方法2：检查命令行（备用）
        if [ -r "$cmdline_file" ]; then
            cmdline=$(tr '\0' ' ' < "$cmdline_file" 2>/dev/null | xargs)
            if [ -n "$cmdline" ]; then
                # 使用单词边界匹配，并排除grep进程
                if ! echo "$cmdline" | grep -q grep && echo " $cmdline " | grep -q " $PROCESS_NAME "; then
                    echo "✅ 进程 '$PROCESS_NAME' 正在运行 (PID: $pid) [方法: 命令行匹配]"
                    exit 0
                fi
            fi
        fi
    fi
done
# === 所有方法都失败 ===
echo "❌ 进程 '$PROCESS_NAME' 未在运行"
exit 1