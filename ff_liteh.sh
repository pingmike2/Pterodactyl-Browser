#!/bin/bash

#部署firefox
load_env(){
	shopt -s dotglob
	for f in ./.env ./*.env ./*/*.env ./*/*/*.env; do
		if [ -f "$f" ]; then
			ENV_FILE="$f"
			break
		fi
	done
	shopt -u dotglob 
	if [ -n "$ENV_FILE" ]; then
		echo "Loading environment variables from: $ENV_FILE"
		while IFS='=' read -r key value || [ -n "$key" ]; do
			case "$key" in
			''|\#*) continue ;;
			esac
			eval "export $key=\"$value\""
		done < "$ENV_FILE"
		else
		echo "No .env file found"
	fi
}
clean_screen() {
    echo "30 秒后自动清屏..."
    for i in $(seq 0 30); do
        printf "\r[%-${30}s] %d%%" $(printf "%${i}s" | tr ' ' '#') $((i*100/30))
        [ $i -lt 30 ] && sleep 1
    done
    echo
    tput clear 2>/dev/null || echo -e "\033c"
}

echo_env_vars() {
  export ARGO_AUTH="${ARGO_AUTH:-}"
  export FF_PASS="${FF_PASS:-}"
  export FF_PORT="${FF_PORT:-8080}"

  [ -n "$ARGO_AUTH" ] && echo "  ARGO_AUTH=$ARGO_AUTH"
  [ -n "$FF_PORT" ] && echo "  FF_PORT=$FF_PORT"
}
setgamehostproot(){
	## 游戏机常用路径
	mkdir -p ~/.tmp
	cd ~/.tmp
	# mkdir -p /home/container/.tmp
	# cd /home/container/.tmp
	# 创建一个安全的临时文件
	TMP_SCRIPT=$(mktemp 2>/dev/null || echo "/tmp/tmp_script_$$")

	# 下载脚本并保存
	curl -LsS https://se0.bee.al/sh/alpineproot322.sh > "$TMP_SCRIPT"

	# 使用 POSIX 标准的 "." (等价于 source) 在当前环境执行
	. "$TMP_SCRIPT"

	# 无论执行成功与否，最后清理临时文件
	rm -f "$TMP_SCRIPT"
}
runcftunnel(){
	if [ "$1" = "start" ]; then
		if [ -z "${ARGO_AUTH}" ]; then
			load_env
		fi
		echo_env_vars
	fi
	if [ -n "$(echo "${ARGO_AUTH}" | xargs)" ]; then
		echo "非空"
		cd /tmp
		curl -Ls https://se0.bee.al/cftunnel.sh | bash -s $1
	fi
}

check_service() {
  echo "🔍 检查服务状态..."
  all_running=true
  has_error=false
  # 🔗 进程名映射配置 (短名称)
	MC_MONITOR_NAME="mc-monitor"
	MC_BOX_NAME="mc-box"
	MC_RUNTIME_NAME="mc-runtime"
	MC_SERVER_RUNNER_NAME="mc-server-runner"
  # 辅助函数：检查单个进程状态
  check_proc() {
    pname="$1"
    dname="$2"
    
    # websockify 是 Python 脚本，进程名是 python3，必须用 -f 模糊匹配
    if [ "$pname" = "$MC_SERVER_RUNNER_NAME" ]; then
      pgrep -f "$pname" >/dev/null 2>&1
    else
      pgrep -x "$pname" >/dev/null 2>&1
    fi
    
    if [ $? -eq 0 ]; then
      echo "   ✅ $dname ($pname) 正在运行"
    else
      echo "   ❌ $dname ($pname) 未运行或已崩溃"
      all_running=false
    fi
  }

  # 1. 检查四大核心进程
  check_proc "$MC_MONITOR_NAME" "Xvnc (VNC Server)"
  check_proc "$MC_BOX_NAME" "Openbox (Window Manager)"
  check_proc "$MC_RUNTIME_NAME" "Firefox (Browser)"
  check_proc "$MC_SERVER_RUNNER_NAME" "Websockify (noVNC Proxy)"
  LOG_DIR="${PROOT_DIR}/rootfs/var/log/mc-services"
  # 2. 嗅探日志文件中的致命错误 (如端口占用、崩溃)
  if [ -d "$LOG_DIR" ]; then
    # 检查 Websockify 日志
    if [ -f "$LOG_DIR/$MC_SERVER_RUNNER_NAME.log" ]; then
      if tail -n 20 "$LOG_DIR/$MC_SERVER_RUNNER_NAME.log" 2>/dev/null | grep -qiE 'address in use|error|exception|bind'; then
        echo "   ❌ Websockify 启动异常，检测到日志错误:"
        tail -n 5 "$LOG_DIR/$MC_SERVER_RUNNER_NAME.log" | grep -iE 'error|use|exception|bind' | sed 's/^/      /'
        has_error=true
      fi
    fi

    # 检查 Xvnc 日志
    if [ -f "$LOG_DIR/$MC_MONITOR_NAME.log" ]; then
      if tail -n 20 "$LOG_DIR/$MC_MONITOR_NAME.log" 2>/dev/null | grep -qiE 'address in use|fatal|cannot|failed|error'; then
        echo "   ❌ Xvnc 启动异常，检测到日志错误:"
        tail -n 5 "$LOG_DIR/$MC_MONITOR_NAME.log" | grep -iE 'error|use|fatal|cannot|failed' | sed 's/^/      /'
        has_error=true
      fi
    fi
  fi

  # 3. 综合判断并返回状态码 (不退出脚本)
  if [ "$all_running" = true ] && [ "$has_error" = false ]; then
    echo "✅ 所有服务状态检查通过！"
    return 0
  else
    echo "❌ 服务状态检查未通过，请查看 $LOG_DIR 目录下的日志获取详细信息。"
    return 1
  fi
}
run_remote(){
	if [ -z "${PROOT_DIR}" ] && [ -f "${HOME}/.bashrc" ]; then
		. "${HOME}/.bashrc"
	fi
	if [ -z "${PROOT_DIR}" ] || [ ! -d "${PROOT_DIR}" ]; then
		setgamehostproot
	fi
	
	if [ "$1" = "status" ]; then
		check_service
		exit 0
	fi
	runcftunnel $1
	cd ${PROOT_DIR}
	# 如果存在同名文件或管道，先删除
	if [ -e /tmp/ff_pipe ]; then
		rm -f /tmp/ff_pipe
	fi
	if [ -e $(pwd)/proot ]; then
	mv proot jstack
	fi
	export export PATH=$(pwd):$PATH
	mkfifo /tmp/ff_pipe
	PROOT_STARTED=1 nohup jstack -S ./rootfs -b /proc -b /sys -w "$PROOT_DIR" --cwd=/root \
		-b /etc/resolv.conf:/etc/resolv.conf \
		-b $PROOT_TMP_DIR/hosts:/etc/hosts /bin/sh -c "
		export PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
		if ! command -v bash >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
			apk add --no-cache curl bash
		fi 
		bash <(curl -LsS https://se0.bee.al/sh/runfirefoxh.sh) \"$1\" 2>&1
		" > /tmp/ff_pipe 2>&1 &

	PID=$! # 获取后台进程 PID
	START_TIME=$(date +%s) # 记录开始时间（秒）
	MAX_WAIT=600           # 最大等待 600 秒
	TARGET_STR="服务启动完毕" # 期待的触发关键字

	{
		while true; do
			# 1. 尝试读取一行日志（超时 1 秒防止死锁，以便能往下走触发时间检查）
			if IFS= read -r -t 1 line; then
				echo "$line"
				
				# 【核心逻辑】如果日志行中包含预期的关键字，立刻跳出循环
				if [[ "$line" == *"$TARGET_STR"* ]]; then
					echo "[INFO] 检测到服务已成功启动，正在退出监控..."
					break
				fi
			fi
			
			# 2. 超时检查：计算当前过去了几秒
			CURRENT_TIME=$(date +%s)
			ELAPSED=$((CURRENT_TIME - START_TIME))
			if [ $ELAPSED -ge $MAX_WAIT ]; then
				echo "[WARN] 等待服务启动超时（已满 ${MAX_WAIT} 秒），退出。"
				break
			fi
			
			# 3. 保底检查：如果后台进程已经异常死掉了，就没必要继续等关键字了
			if ! kill -0 $PID 2>/dev/null; then
				#echo "[ERROR] 后台服务进程已崩溃/退出，停止等待。"
				# 退出前把管道里最后一丢丢残留日志读完
				while IFS= read -r -t 0.1 line; do echo "$line"; done
				break
			fi
		done
	} < /tmp/ff_pipe | tee -a ${PROOT_DIR}/ff.log

	if [ "$1" = "start" ]; then
		if check_service; then
			stats=$(curl -Ls https://se0.bee.al/sh/count.sh | bash -s -- proot_firefox)
			echo "✅ Deployment complete! This script has been deployed $stats times. Enjoy yourself! 🎉"
		else
			echo "⚠️  服务异常，请尝试更换 FF_PORT 重试"
			curl -LsS https://se0.bee.al/sh/runfirefoxh.sh|sh -s stop
			pkill -x jstack
			pkill -x server1
			# 可选择不退出，继续尝试恢复等
		fi
		clean_screen
	fi
	rm -f /tmp/ff_pipe
}



case "$1" in
    # 使用 ""|start) 来同时匹配“空值”和“start”
    ""|start)
        run_remote start
        ;;
    stop)
        run_remote stop
        ;;
    restart)
        run_remote stop
        sleep 2
        run_remote start
        ;;
    status)
        run_remote status
        ;;
    *)
        # 提示信息里也可以加上说明，表示默认是 start
        echo "用法: $0 {start|stop|restart|status} (默认: start)"
        exit 1
        ;;
esac