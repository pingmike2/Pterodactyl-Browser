#!/bin/sh
filename=ago
ARCH=$(uname -m)
if [ "${ARCH#arm}" != "$ARCH" ] || [ "$ARCH" = "aarch64" ]; then
   filename="agoarm64"
fi
outputname=server1

if [ "${1:-}" = "stop" ]; then
  # 依次尝试不同命令
  if command -v killall >/dev/null 2>&1; then
    killall "$outputname" 2>/dev/null
  elif command -v pkill >/dev/null 2>&1; then
    pkill -x "$outputname" 2>/dev/null
  else
    ps aux 2>/dev/null | grep -v grep | grep "$outputname" | awk '{print $2}' | xargs -r kill 2>/dev/null || true
  fi
  
  echo "🛑 停止argo服务"
  exit 0
fi

download(){
	if command -v wget > /dev/null; then
    wget -qc https://gbjs.serv00.net/bin/${filename} -O "$outputname" || { echo "下载失败"; exit 1; }
	elif command -v curl > /dev/null; then
		curl -C - -LsS https://gbjs.serv00.net/bin/${filename} -o "$outputname" || { echo "下载失败"; exit 1; }
	else
		echo "无法找到 wget 或 curl，下载失败"
		exit 1
	fi
}
check_process() {
   if command -v curl >/dev/null 2>&1; then
    (curl -LsSk https://gbjs.serv00.net/sh/ps.sh)|sh -s -- "$outputname"
    if [ $? -eq 0 ]; then
        exit 1
    fi
   fi
}
check_process
if [ -z "$ARGO_AUTH" ]; then
    echo "错误：ARGO_AUTH 未赋值"
    exit 1
fi

if test -f "$outputname"; then
    echo "file exist,skipping download"
else
    download
    chmod +x "./$outputname"
fi


nohup "./$outputname" tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token "$ARGO_AUTH" >/dev/null 2>&1 &

sleep 2

if command -v ps >/dev/null 2>&1; then
    echo "checking process"
    ps -ef | grep "$ARGO_AUTH" | grep -v grep
fi