#!/bin/bash

# stats_counter.sh - 统计计数器脚本（支持返回值）
# 其他脚本可以通过以下方式获取数值：
# 1. 通过标准输出: value=$(./stats_counter.sh field_name)
# 2. 通过退出码: ./stats_counter.sh field_name; value=$?

# 设置API端点
QUERY_URL="https://se0.bee.al/summary/query.php"
UPLOAD_URL="https://se0.bee.al/summary/upload.php"


# 确定字段名
if [ -n "$1" ]; then
    FIELD_NAME="$1"
elif [ -n "$NAME" ]; then
    FIELD_NAME="$NAME"
else
    echo "错误: 请指定字段名" >&2
    exit 255
fi

# 安静模式标志（-q参数）
QUIET_MODE=false
if [ "$2" = "-q" ] || [ "$2" = "--quiet" ]; then
    QUIET_MODE=true
fi

# 检查curl
if ! command -v curl &> /dev/null; then
    echo "错误: 需要curl命令" >&2
    exit 254
fi

# 函数：查询当前值
query_value() {
    local response
    response=$(curl -s -G --data-urlencode "name=$FIELD_NAME" "$QUERY_URL")
    
    if [ $? -ne 0 ]; then
        echo "网络请求失败" >&2
        return 1
    fi
    
    if [[ "$response" == *"未找到"* ]]; then
        CURRENT_VALUE=0
        IS_NEW_FIELD=true
        return 0
    fi
    
    if [[ "$response" == *"错误"* ]] || [[ "$response" == *"参数缺失"* ]]; then
        echo "查询失败: $response" >&2
        return 1
    fi
    
    if [[ "$response" =~ ^[0-9]+$ ]]; then
        CURRENT_VALUE=$response
        IS_NEW_FIELD=false
        return 0
    fi
    
    echo "无效的响应格式: $response" >&2
    return 1
}

# 函数：更新值
update_value() {
    local new_value=$1
    local response
    response=$(curl -s -X POST -d "name=$FIELD_NAME" -d "value=$new_value" "$UPLOAD_URL")
    
    if [ $? -ne 0 ] || [[ "$response" != *"数据已保存"* ]]; then
        echo "更新失败: $response" >&2
        return 1
    fi
    return 0
}

# 主执行流程
main() {
    # 查询当前值
    if ! query_value; then
        exit 253
    fi
    
    # 计算新值
    NEW_VALUE=$((CURRENT_VALUE + 1))
    
    # 更新值
    if ! update_value $NEW_VALUE; then
        exit 252
    fi
    
    # 输出结果
    # if [ "$IS_NEW_FIELD" = true ]; then
    #     [ "$QUIET_MODE" = false ] && echo "🆕 创建字段 '$FIELD_NAME'，值: $NEW_VALUE" >&2
    # else
    #     [ "$QUIET_MODE" = false ] && echo "计数器 '$FIELD_NAME': $CURRENT_VALUE → $NEW_VALUE" >&2
    # fi
    
    # 返回当前数值（更新前的值）
    echo $NEW_VALUE
    exit 0
}

main