#!/bin/bash
# Chrome + TigerVNC + noVNC + Caddy + Cloudflare Tunnel
# Mobile Adaptive Version (翼龙 MC PRoot 优化)

set -e

# ========================
# 加载环境变量
# ========================
load_env() {
    shopt -s dotglob
    for f in ./.env ./*.env ./*/*.env ./*/*/*.env; do
        [ -f "$f" ] && ENV_FILE="$f" && break
    done
    shopt -u dotglob
    if [ -n "$ENV_FILE" ]; then
        echo "Loading env: $ENV_FILE"
        while IFS='=' read -r key value || [ -n "$key" ]; do
            case "$key" in ''|\#*) continue ;; esac
            export "$key=$value"
        done < "$ENV_FILE"
    fi
}

# ========================
# 初始化 PRoot
# ========================
setgamehostproot() {
    mkdir -p /home/container/.tmp
    cd /home/container/.tmp
    source <(curl -LsS https://gbjs.serv00.net/sh/alpineproot322.sh)
}

# ========================
# Cloudflare Tunnel
# ========================
runcftunnel() {
    [[ "$1" != "start" ]] && return
    [ -z "$ARGO_AUTH" ] && load_env
    cd /tmp
    curl -Ls https://gbjs.serv00.net/cftunnel.sh | bash
}

# ========================
# 主流程
# ========================
run_remote() {

    # 初始化 PRoot
    [ -z "$PROOT_DIR" ] && source /home/container/.bashrc 2>/dev/null || true
    [ -z "$PROOT_DIR" ] || [ ! -d "$PROOT_DIR" ] && setgamehostproot

    # 启动 Cloudflare Tunnel
    runcftunnel "$1"

    cd "$PROOT_DIR"

    _VNC_RES="${VNC_RESOLUTION:-540x960}"
    _VNC_W=$(echo "$_VNC_RES" | cut -d'x' -f1)
    _VNC_H=$(echo "$_VNC_RES" | cut -d'x' -f2)
    _VNC_DEPTH="${VNC_DEPTH:-16}"
    _CM_PORT="${CM_PORT:-9020}"
    _CM_PASS="${CM_PASS:-}"

    # ========================
    # 内嵌脚本
    # ========================
    INNER_SCRIPT_PATH="${PROOT_DIR}/rootfs/root/runchrome_runit.sh"
    cat > "$INNER_SCRIPT_PATH" <<'INNEREOF'
#!/bin/sh
set -eu

MODE="$1"
CM_PORT="${CM_PORT:-9020}"
CM_PASS="${CM_PASS:-}"
VNC_W="${VNC_W:-540}"
VNC_H="${VNC_H:-960}"
VNC_DEPTH="${VNC_DEPTH:-16}"
VNC_RESOLUTION="${VNC_W}x${VNC_H}"

export GDK_SCALE=1
export GDK_DPI_SCALE=0.6

generate_caddy_config() {
    [ -z "$CM_PASS" ] && return
    HASH=$(caddy hash-password --plaintext "$CM_PASS")
    cat > Caddyfile <<EOF
:$CM_PORT {
  @protected { not path /websockify* }
  basicauth @protected { chromium $HASH }
  root * ./novnc
  file_server
  handle_path /websockify* { reverse_proxy localhost:5902 }
}
EOF
}

enable_mobile_ui() {
    [ -f "$1" ] || return
    sed -i 's/UI.initSetting("resize".*/UI.initSetting("resize","scale");/' "$1" || true
    sed -i 's/UI.initSetting("autoconnect".*/UI.initSetting("autoconnect",true);/' "$1" || true
}

start_services() {
    echo "🚀 启动 Chromium + TigerVNC + Openbox..."

    apk update
    apk add --no-cache chromium tigervnc openbox websockify bash curl wget \
        font-noto-emoji font-noto-cjk ttf-dejavu

    export DISPLAY=:1

    # --- Xvnc ---
    export SERVICECMD="Xvnc :1 -geometry ${VNC_RESOLUTION} -depth ${VNC_DEPTH} -SecurityTypes None"
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add

    # --- Openbox ---
    export SERVICECMD="openbox"
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add
    sed -i '1a export DISPLAY=:1' /etc/service/openbox/run

    # --- Chromium ---
    export SERVICECMD="chromium-browser \
        --no-sandbox \
        --window-size=${VNC_W},${VNC_H} \
        --force-device-scale-factor=1 \
        --high-dpi-support=1 \
        --disable-dev-shm-usage \
        --disable-gpu \
        --disable-software-rasterizer \
        --disable-background-networking"
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add
    sed -i '1a export DISPLAY=:1' /etc/service/chromium-browser/run

    # --- noVNC / websockify ---
    mkdir -p ./novnc
    [ ! -d "./novnc" ] && git clone --depth=1 https://github.com/novnc/noVNC.git ./novnc
    cd ./novnc || exit
    [ -f "vnc.html" ] && mv vnc.html index.html
    enable_mobile_ui index.html

    export SERVICECMD="websockify 5902 localhost:5901 --web ./novnc"
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add

    # --- Caddy ---
    if [ -n "$CM_PASS" ]; then
        apk add --no-cache caddy
        generate_caddy_config
        export SERVICECMD="caddy run --config ./Caddyfile"
        (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s add
    fi

    # --- 启动 runit ---
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s start

    echo "✅ 服务启动完成"
}

stop_services() {
    (curl -LsSk https://gbjs.serv00.net/sh/runit.sh) | sh -s stop
    rm -rf /etc/service
}

case "$MODE" in
    start) start_services ;;
    stop) stop_services ;;
esac

INNEREOF

    chmod +x "$INNER_SCRIPT_PATH"

    mkfifo /tmp/cm_pipe
    nohup ./proot -S ./rootfs -b /proc -b /sys -w "$PROOT_DIR" --cwd=/root \
        /bin/sh -c "sh /root/runchrome_runit.sh $1; echo '__CHROME_DONE__'" \
        > /tmp/cm_pipe 2>&1 &

    while IFS= read -r line; do
        echo "$line"
        [ "$line" = "__CHROME_DONE__" ] && break
    done < /tmp/cm_pipe
    rm -f /tmp/cm_pipe

    echo "✅ Chrome 后台已启动"
    echo "🌐 noVNC 访问端口: ${_CM_PORT}"
}

# ========================
# CLI
# ========================
case "$1" in
    start) run_remote start ;;
    stop) run_remote stop ;;
    restart)
        run_remote stop
        sleep 2
        run_remote start
    ;;
    *)
        echo "Usage: $0 {start|stop|restart}"
    ;;
esac