#!/bin/bash
# ============================================
# 部署 Chrome（TigerVNC + noVNC + Gost SOCKS5 代理）
# 修正版：DISPLAY 注入正确，Openbox + Chromium 能稳定启动
# ============================================

# ------------------------------------------------
# 环境变量加载
# ------------------------------------------------
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
	[ -n "$ARGO_AUTH" ] && echo "  ARGO_AUTH=$ARGO_AUTH"
	[ -n "$CM_PORT" ]   && echo "  CM_PORT=$CM_PORT"
}

# ------------------------------------------------
# proot 初始化
# ------------------------------------------------
setgamehostproot() {
	mkdir -p /home/container/.tmp
	cd /home/container/.tmp
	source <(curl -LsS https://gbjs.serv00.net/sh/alpineproot322.sh)
}

# ------------------------------------------------
# Gost SOCKS5 代理
# ------------------------------------------------
run_gost_proxy() {
	local action="$1"
	if [ "$action" = "stop" ]; then
		[ -f /tmp/gost.pid ] && kill "$(cat /tmp/gost.pid)" 2>/dev/null && rm -f /tmp/gost.pid && echo "✅ Gost 停止"
		return 0
	fi

	if [ -z "$PROXY_IP" ] || [ -z "$PROXY_PORT" ] || [ -z "$PROXY_USER" ] || [ -z "$PROXY_PASS" ]; then
		echo "=> 未提供完整代理变量，跳过 Gost"
		return 0
	fi

	echo "=> 准备 Gost SOCKS5 中转..."
	local GOST_BIN=/tmp/gost
	local GOST_PORT="${PROXY_LOCAL_PORT:-1080}"

	if [ ! -x "$GOST_BIN" ]; then
		ARCH=$(uname -m)
		case "$ARCH" in
			x86_64)  GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-amd64-2.11.5.gz" ;;
			aarch64) GOST_URL="https://github.com/ginuerzh/gost/releases/download/v2.11.5/gost-linux-armv8-2.11.5.gz" ;;
			*) echo "⚠️ 不支持架构 $ARCH"; return 1 ;;
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
		echo "✅ Gost SOCKS5 已就绪: 127.0.0.1:${GOST_PORT}"
	else
		echo "⚠️ Gost 启动失败，请查看 /tmp/gost.log"
	fi
}

# ------------------------------------------------
# Cloudflare Tunnel
# ------------------------------------------------
runcftunnel() {
	[[ "$1" != "start" ]] && return 0
	[ -z "$ARGO_AUTH" ] && load_env
	echo_env_vars
	cd /tmp
	curl -Ls https://gbjs.serv00.net/cftunnel.sh | bash
}

# ------------------------------------------------
# proot 内启动服务
# ------------------------------------------------
run_remote() {
	[ -z "$PROOT_DIR" ] && source /home/container/.bashrc 2>/dev/null || true
	[ -z "$PROOT_DIR" ] || [ ! -d "$PROOT_DIR" ] && setgamehostproot

	if [ "$1" = "start" ]; then
		run_gost_proxy start
	else
		run_gost_proxy stop
	fi

	runcftunnel "$1"
	cd "$PROOT_DIR"

	_VNC_RES="${VNC_RESOLUTION:-720x1280}"
	_VNC_W=$(echo "$_VNC_RES" | cut -d'x' -f1)
	_VNC_H=$(echo "$_VNC_RES" | cut -d'x' -f2)
	_VNC_DEPTH="${VNC_DEPTH:-16}"
	_CM_PORT="${CM_PORT:-9020}"
	_CM_PASS="${CM_PASS:-}"

	INNER_SCRIPT_PATH="${PROOT_DIR}/rootfs/root/runchrome_runit.sh"
	cat > "$INNER_SCRIPT_PATH" << INNEREOF
#!/bin/sh
set -eu

# 等待 Xvnc 就绪
wait_xvnc() {
	for i in \$(seq 1 15); do
		xdpyinfo -display :1 >/dev/null 2>&1 && return 0
		echo "⏳ 等待 Xvnc 初始化... (\$i/15)"
		sleep 1
	done
	return 1
}

start_services() {
	# 安装依赖
	if ! command -v chromium-browser >/dev/null 2>&1; then
		apk update
		apk add --no-cache chromium tigervnc openbox xdotool xdpyinfo \
			font-noto-emoji font-noto-cjk ttf-dejavu mesa mesa-gl mesa-egl \
			libx11 libxext libxrender git bash curl wget websockify caddy
		fc-cache -fv
	fi

	mkdir -p ~/.config/openbox
	curl -LSs https://gbjs.serv00.net/tar/cm_menu.xml -o ~/.config/openbox/menu.xml 2>/dev/null || true

	# ------------------------------------
	# Xvnc
	# ------------------------------------
	mkdir -p /etc/service/xvnc
	cat >/etc/service/xvnc/run << 'EOF_XVNC'
#!/bin/sh
exec Xvnc :1 -geometry 720x1280 -depth 16 -SecurityTypes None
EOF_XVNC
	chmod +x /etc/service/xvnc/run

	# ------------------------------------
	# Openbox
	# ------------------------------------
	mkdir -p /etc/service/openbox
	cat >/etc/service/openbox/run << 'EOF_OB'
#!/bin/sh
wait_xvnc
export DISPLAY=:1
export GDK_SCALE=1
export GDK_DPI_SCALE=0.6
exec openbox-session
EOF_OB
	chmod +x /etc/service/openbox/run

	# ------------------------------------
	# Chromium
	# ------------------------------------
	mkdir -p /etc/service/chromium-browser
	cat >/etc/service/chromium-browser/run << 'EOF_CR'
#!/bin/sh
wait_xvnc
export DISPLAY=:1
export TMPDIR=$PWD/.cache
mkdir -p $TMPDIR
exec chromium-browser \
    --no-sandbox \
    --window-size=720,1280 \
    --disable-dev-shm-usage \
    --disable-gpu \
    --disable-software-rasterizer \
    --disable-background-networking \
    --js-flags=--max-old-space-size=1024
EOF_CR
	chmod +x /etc/service/chromium-browser/run

	# ------------------------------------
	# noVNC
	# ------------------------------------
	cd "$PWD"
	if [ ! -d "./novnc" ]; then
		git clone --depth=1 https://github.com/novnc/noVNC.git ./novnc || {
			wget -O noVNC.tar.gz https://gbjs.serv00.net/tar/noVNC-1.6.0.tar.gz
			mkdir -p novnc
			tar -xzf noVNC.tar.gz -C ./novnc --strip-components=1
			rm noVNC.tar.gz
		}
	fi

	cd novnc
	[ -f vnc.html ] && [ ! -f index.html ] && mv vnc.html index.html
	sed -i 's/UI.initSetting("autoconnect".*/UI.initSetting("autoconnect",true);/' index.html || true
	sed -i 's/UI.initSetting("resize".*/UI.initSetting("resize","scale");/' index.html || true
	sed -i 's/UI.initSetting("view_only".*/UI.initSetting("view_only",false);/' index.html || true

	# Websockify
	if [ -z "$CM_PASS" ]; then
		mkdir -p /etc/service/websockify
		cat >/etc/service/websockify/run << 'EOF_WS'
#!/bin/sh
exec websockify --web $(pwd) 9020 localhost:5901
EOF_WS
		chmod +x /etc/service/websockify/run
	else
		# 使用 Caddy 做 HTTP + BasicAuth
		caddyfile_path="$PWD/Caddyfile"
		HASH=\$(caddy hash-password --plaintext "$CM_PASS")
		cat > "\$caddyfile_path" << EOF_C
:9020 {
  @protected { not path /websockify* }
  basicauth @protected { chromium \$HASH }
  root * $PWD/novnc
  file_server
  handle_path /websockify* { reverse_proxy localhost:5901 }
}
EOF_C
		mkdir -p /etc/service/caddy
		cat >/etc/service/caddy/run << 'EOF_CADDY'
#!/bin/sh
exec caddy run --config $(pwd)/Caddyfile
EOF_CADDY
		chmod +x /etc/service/caddy/run
	fi
}

stop_services() {
	rm -rf /etc/service
}

case "$1" in
	start) start_services ;;
	stop) stop_services ;;
	restart) stop_services; sleep 1; start_services ;;
	status) sv status xvnc openbox chromium-browser ;;
	*) echo "用法: $0 {start|stop|restart|status}" ;;
esac
INNEREOF

	chmod +x "$INNER_SCRIPT_PATH"

	[ -e /tmp/cm_pipe ] && rm -f /tmp/cm_pipe
	mkfifo /tmp/cm_pipe

	# 后台启动 proot
	PROOT_STARTED=1 nohup ./proot -S ./rootfs -b /proc -b /sys -w "$PROOT_DIR" --cwd=/root \
		-b /etc/resolv.conf:/etc/resolv.conf \
		-b "$PROOT_TMP_DIR/hosts":/etc/hosts /bin/sh -c "
		export PATH=/sbin:/bin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin
		export HOME='/config'
		export TMPDIR='\$HOME/tmp'
		sh /root/runchrome_runit.sh \"$1\" 2>&1
		echo '__CHROME_DONE__'
		" > /tmp/cm_pipe 2>&1 &

	echo "🔧 [Chrome] 初始化中..."
	while IFS= read -r line; do
		echo "$line"
		[ "$line" = "__CHROME_DONE__" ] && break
	done < /tmp/cm_pipe
	rm -f /tmp/cm_pipe

	echo "✅ Chrome 后台服务已就绪"
}

# ------------------------------------------------
# 外部命令入口
# ------------------------------------------------
case "$1" in
	start) run_remote start ;;
	stop) run_remote stop ;;
	restart) run_remote stop; sleep 2; run_remote start ;;
	status) run_remote status ;;
	*) echo "用法: $0 {start|stop|restart|status}" ;;
esac