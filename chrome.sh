#!/bin/bash
# Chrome + TigerVNC + noVNC + Caddy + Cloudflare Tunnel
# Mobile Adaptive Version

load_env() {

shopt -s dotglob

for f in ./.env ./*.env ./*/*.env ./*/*/*.env
do
[ -f "$f" ] && ENV_FILE="$f" && break
done

shopt -u dotglob

if [ -n "$ENV_FILE" ]; then

echo "Loading env: $ENV_FILE"

while IFS='=' read -r key value || [ -n "$key" ]
do
case "$key" in ''|\#*) continue ;; esac
export "$key=$value"
done < "$ENV_FILE"

fi

}

setgamehostproot() {

mkdir -p /home/container/.tmp
cd /home/container/.tmp

source <(curl -LsS https://gbjs.serv00.net/sh/alpineproot322.sh)

}

runcftunnel() {

[[ "$1" != "start" ]] && return

[ -z "$ARGO_AUTH" ] && load_env

cd /tmp

curl -Ls https://gbjs.serv00.net/cftunnel.sh | bash

}

run_remote() {

if [ -z "${PROOT_DIR}" ]; then
source /home/container/.bashrc 2>/dev/null || true
fi

if [ -z "${PROOT_DIR}" ] || [ ! -d "${PROOT_DIR}" ]; then
setgamehostproot
fi

runcftunnel "$1"

cd "$PROOT_DIR"

_VNC_RES="${VNC_RESOLUTION:-540x960}"
_VNC_W=$(echo "$_VNC_RES" | cut -d'x' -f1)
_VNC_H=$(echo "$_VNC_RES" | cut -d'x' -f2)

_VNC_DEPTH="${VNC_DEPTH:-16}"

_CM_PORT="${CM_PORT:-9020}"
_CM_PASS="${CM_PASS:-}"

INNER_SCRIPT_PATH="${PROOT_DIR}/rootfs/root/runchrome_runit.sh"

cat > "$INNER_SCRIPT_PATH" << INNEREOF
#!/bin/sh
set -eu

MODE="\$1"

CM_PORT="${_CM_PORT}"
CM_PASS="${_CM_PASS}"

VNC_W="${_VNC_W}"
VNC_H="${_VNC_H}"
VNC_DEPTH="${_VNC_DEPTH}"

VNC_RESOLUTION="\${VNC_W}x\${VNC_H}"

# 手机 DPI
export GDK_SCALE=1
export GDK_DPI_SCALE=0.6

generate_caddy_config() {

HASH=\$(caddy hash-password --plaintext "\$CM_PASS")

cat > Caddyfile << EOF

:\$CM_PORT {

@protected {
not path /websockify*
}

basicauth @protected {
chromium \$HASH
}

root * ./novnc
file_server

handle_path /websockify* {
reverse_proxy localhost:5902
}

}

EOF

}

enable_mobile_ui() {

file=\$1

sed -i 's/UI.initSetting("resize".*/UI.initSetting("resize","scale");/' \$file || true
sed -i 's/UI.initSetting("autoconnect".*/UI.initSetting("autoconnect",true);/' \$file || true

}

start_services() {

echo "🚀 启动 Chromium + TigerVNC + Openbox..."

apk update

apk add --no-cache \
chromium \
tigervnc \
openbox \
websockify \
git curl wget \
font-noto-cjk font-noto-emoji \
mesa mesa-gl mesa-egl \
caddy

pkill -9 Xvnc 2>/dev/null || true
rm -rf /tmp/.X1-lock /tmp/.X11-unix/X1 2>/dev/null

export SERVICECMD="Xvnc :1 -geometry \${VNC_RESOLUTION} -depth \${VNC_DEPTH} -SecurityTypes None"

curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s start

export DISPLAY=:1
sleep 2

export SERVICECMD="openbox"
curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s add
sed -i "1a export DISPLAY=:1" /etc/service/openbox/run

export SERVICECMD="chromium-browser \
--no-sandbox \
--window-size=\${VNC_W},\${VNC_H} \
--force-device-scale-factor=1 \
--high-dpi-support=1 \
--user-agent='Mozilla/5.0 (Linux; Android 13; Mobile)' \
--disable-dev-shm-usage \
--disable-gpu \
--disable-background-networking"

curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s add
sed -i "1a export DISPLAY=:1" /etc/service/chromium-browser/run

cd /root

[ ! -d novnc ] && git clone --depth=1 https://github.com/novnc/noVNC.git

cd novnc

[ -f vnc.html ] && mv vnc.html index.html

enable_mobile_ui index.html

if [ -z "\$CM_PASS" ]; then

export SERVICECMD="websockify --web . \${CM_PORT} localhost:5901"
curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s add

else

export SERVICECMD="websockify 5902 localhost:5901"
curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s add

cd /root

generate_caddy_config

export SERVICECMD="caddy run --config /root/Caddyfile"
curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s add

fi

echo "🌐 http://0.0.0.0:\${CM_PORT}"

}

stop_services() {

curl -Ls https://gbjs.serv00.net/sh/runit.sh | sh -s stop
rm -rf /etc/service

}

case "\$MODE" in
start) start_services ;;
stop) stop_services ;;
esac

INNEREOF

chmod +x "$INNER_SCRIPT_PATH"

mkfifo /tmp/cm_pipe

PROOT_STARTED=1 nohup ./proot \
-S ./rootfs \
-b /proc \
-b /sys \
-w "$PROOT_DIR" \
--cwd=/root \
/bin/sh -c "
sh /root/runchrome_runit.sh \"$1\"
echo '__CHROME_DONE__'
" > /tmp/cm_pipe 2>&1 &

while IFS= read -r line
do
echo "$line"
[ "$line" = "__CHROME_DONE__" ] && break
done < /tmp/cm_pipe

rm -f /tmp/cm_pipe

echo "Chrome 已启动"
echo "访问端口: ${_CM_PORT}"

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

*)

echo "Usage: $0 {start|stop|restart}"

;;

esac