#!/bin/bash
# 部署 Chrome（TigerVNC + Gost SOCKS5 代理中转）竖屏版

# ============================================================
# 环境变量加载
# ============================================================
load_env() {
	shopt -s dotglob
	for f in ./.env ./*.env ./*/*.env ./*/*/*.env; do
		[ -f "$f" ] && ENV_FILE="$f" && break
	done
	shopt -u dotglob
	if [ -n "$ENV_FILE" ]; then
		echo "Loading environment variables from: $ENV_FILE"
		while IFS='=' read -r key value || [ -n "$key" ]; do
			case "$key" in ''|\#*) continue ;; esac
			export "$key=$value"
		done < "$ENV_FILE"
	else
		echo "No .env file found"
	fi
}

echo_env_vars() {
	export ARGO_AUTH="${ARGO_AUTH:-''}"
	export CM_PASS="${CM_PASS:-Ww112211}"
	export CM_PORT="${CM_PORT:-9020}"

	# ✅ 新增变量
	export VNC_RES="${VNC_RES:-720x1280}"
	export VNC_DEPTH="${VNC_DEPTH:-24}"

	[ -n "$ARGO_AUTH" ] && echo "  ARGO_AUTH=$ARGO_AUTH"
	[ -n "$CM_PORT" ]   && echo "  CM_PORT=$CM_PORT"
	echo "  VNC_RES=$VNC_RES"
	echo "  VNC_DEPTH=$VNC_DEPTH"
}

# ============================================================
# proot 环境初始化
# ============================================================
setgamehostproot() {
	mkdir -p /home/container/.tmp
	cd /home/container/.tmp
	source <(curl -LsS https://gbjs.serv00.net/sh/alpineproot322.sh)
}

# ============================================================
# Gost SOCKS5 代理中转
# ============================================================
run_gost_proxy() {
	local action="$1"

	if [ "$action" = "stop" ]; then
		if [ -f /tmp/gost.pid ]; then
			kill "$(cat /tmp/gost.pid)" 2>/dev/null && echo "✅ Gost 代理已停止"
			rm -f /tmp/gost.pid
		fi
		return 0
	fi

	if [ -z "$PROXY_IP" ] || [ -z "$PROXY_PORT" ] || \
	   [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
		echo "=> 未提供完整代理变量，跳过代理中转。"
		return 0
	fi

	echo "=> 检测到代理配置，正在准备 Gost SOCKS5 中转..."

	local GOST_BIN=/tmp/gost
	local GOST_PORT="${PROXY_LOCAL_PORT:-1080}"

	if [ ! -x "$GOST_BIN" ]; then
		echo "   正在下载 Gost 二进制..."
		local ARCH GOST_URL
		ARCH=$(uname -m)
		case "$ARCH" in
			x86_64)  GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz" ;;
			aarch64) GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz" ;;
			*)
				echo "   ⚠️  不支持的架构 $ARCH，跳过。"
				return 1
				;;
		esac
		curl -Ls "$GOST_URL" | gunzip > "$GOST_BIN"
		chmod +x "$GOST_BIN"
	fi

	[ -f /tmp/gost.pid ] && kill "$(cat /tmp/gost.pid)" 2>/dev/null && rm -f /tmp/gost.pid

	nohup "$GOST_BIN" \
		-L "socks5://:${GOST_PORT}" \
		-F "socks5://${PROXY_USER}:${PROXY_PASS}@${PROXY_IP}:${PROXY_PORT}" \
		> /tmp/gost.log 2>&1 &
	echo $! > /tmp/gost.pid

	sleep 1
	if kill -0 "$(cat /tmp/gost.pid)" 2>/dev/null; then
		echo -e "\033[32m✅ Gost SOCKS5 中转已就绪！监听端口：${GOST_PORT}\033[0m"
		echo "   协议: SOCKS5    地址: 127.0.0.1    端口: ${GOST_PORT}    密码: (留空)"
	else
		echo "⚠️  Gost 启动失败，请查看 /tmp/gost.log"
	fi
}

# ============================================================
# Cloudflare Tunnel
# ============================================================
runcftunnel() {
	[[ "$1" != "start" ]] && return 0
	[ -z "${ARGO_AUTH}" ] && load_env
	echo_env_vars
	cd /tmp
	curl -Ls https://gbjs.serv00.net/cftunnel.sh | bash
}

# ============================================================
# 主流程
# ============================================================
run_remote() {
	if [ -z "${PROOT_DIR}" ]; then
		source /home/container/.bashrc 2>/dev/null || true
	fi
	if [ -z "${PROOT_DIR}" ] || [ ! -d "${PROOT_DIR}" ]; then
		setgamehostproot
	fi

	# ✅ 新增解析
	VNC_RES="${VNC_RES:-720x1280}"
	VNC_DEPTH="${VNC_DEPTH:-16}"
	_VNC_W="${VNC_RES%x*}"
	_VNC_H="${VNC_RES#*x}"
	_VNC_RES="${_VNC_W}x${_VNC_H}"
	_VNC_DEPTH="${VNC_DEPTH}"

	if [ "$1" = "start" ]; then
		run_gost_proxy start
	else
		run_gost_proxy stop
	fi

	runcftunnel "$1"
	cd "${PROOT_DIR}"

	_CM_PORT="${CM_PORT:-9020}"
	_CM_PASS="${CM_PASS:-}"

	INNER_SCRIPT_PATH="${PROOT_DIR}/rootfs/root/runchrome_runit.sh"

	cat > "$INNER_SCRIPT_PATH" <<INNEREOF
#!/bin/sh
set -eu

MODE="\$1"
CM_PORT="\${CM_PORT:-9020}"
CM_PASS="\${CM_PASS:-Ww112211}"

# ✅ 使用外部传入
VNC_W=${_VNC_W}
VNC_H=${_VNC_H}
VNC_RES="${_VNC_RES}"
VNC_DEPTH=${_VNC_DEPTH}

export DISPLAY=:1
export GDK_SCALE=1
export GDK_DPI_SCALE=1

generate_caddy_config() {
  [ -z "\$CM_PASS" ] && echo "CM_PASS not set" && return 1
  HASH=\$(caddy hash-password --plaintext "\$CM_PASS")
  [ -z "\$HASH" ] && echo "hash failed" && return 1
  rm -rf \$1/Caddyfile
  cat > \$1/Caddyfile << EOF
:\$CM_PORT {
  @protected {
    not path /websockify*
  }
  basicauth @protected {
    admin \$HASH
  }
  root * \$1/novnc
  file_server
  handle_path /websockify* {
    reverse_proxy localhost:5902
  }
}
EOF
  echo "✅ Caddyfile 已生成，端口 \$CM_PORT，用户名 admin"
}

enable_autoconnect() {
  local file="\${1:-index.html}"
  if command -v perl >/dev/null 2>&1; then
    perl -i -pe 's/.*defaults\["autoconnect"\].*//g; \$_ = "defaults[\"autoconnect\"] = true;\n" if \$. == 85;' "\$file" 2>/dev/null || true
  fi
}

start_services() {
  echo "🚀 启动 Chromium + TigerVNC + Openbox..."

  if ! command -v chromium-browser >/dev/null 2>&1; then
    apk update
    apk add --no-cache chromium git bash curl wget \
      font-noto-emoji font-noto-cjk ttf-dejavu \
      mesa mesa-gl mesa-egl libx11 libxext libxrender \
      tigervnc openbox xdotool xdpyinfo pciutils-dev st \
      websockify
    fc-cache -fv
  else
    echo "✅ 软件包已存在，跳过安装"
  fi

  export SERVICECMD="Xvnc :1 -geometry \${VNC_RES} -depth \${VNC_DEPTH} -SecurityTypes None"
  (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s start

  export SERVICECMD="openbox"
  (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add

  export SERVICECMD="chromium-browser \
    --no-sandbox \
    --window-size=\${VNC_W},\${VNC_H}"
  (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add

  export SERVICECMD="websockify --web ./novnc \${CM_PORT} localhost:5901"
  (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add
}

case "\$MODE" in
  start) start_services ;;
  stop) ;;
esac
INNEREOF

	chmod +x "$INNER_SCRIPT_PATH"

	PROOT_STARTED=1 nohup ./proot -S ./rootfs -b /proc -b /sys -w "$PROOT_DIR" --cwd=/root \
		-b /etc/resolv.conf:/etc/resolv.conf \
		-b "$PROOT_TMP_DIR/hosts":/etc/hosts /bin/sh -c "
		sh /root/runchrome_runit.sh \"$1\"
		" &
}

case "$1" in
	start)
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
		echo "用法: $0 {start|stop|restart|status}"
		echo "支持变量:"
		echo "  VNC_RES=900x1600"
		echo "  VNC_DEPTH=24"
		exit 1
		;;
esac