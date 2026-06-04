#!/bin/sh

# ⚠️ 已移除 set -e，防止错误被屏蔽导致难以排查

MODE="$1"
FF_PORT="${FF_PORT:-8080}"
FF_PASS="${FF_PASS:-}"
DISPLAY_NUM="1"
VNC_PORT=$((FF_PORT + DISPLAY_NUM))

export HOME="/config"
export TMPDIR="$HOME/tmp"
echo  'export HOME="/config"'>/root/.bashrc
echo  'export TMPDIR="/config/tmp"'>>/root/.bashrc
[ -d $TMPDIR ] || mkdir -p $TMPDIR
[ -d $HOME ] || mkdir -p $HOME
# PID 文件路径
FIREFOX_PID_FILE="/tmp/firefox.pid"
XVNCSERVER_PID_FILE="/tmp/xvncserver.pid"
WEBSOCKIFY_PID_FILE="/tmp/websockify.pid"
OPENBOX_PID_FILE="/tmp/openbox.pid"

# 🔗 进程名映射配置 (短名称)
MC_MONITOR_NAME="mc-monitor"
MC_BOX_NAME="mc-box"
MC_RUNTIME_NAME="mc-runtime"
MC_SERVER_RUNNER_NAME="mc-server-runner"

# 📍 伪装目录与日志目录定义
FF_FAKE_DIR="/usr/lib/mc-core"
LOG_DIR="/var/log/mc-services"

# ================= 核心辅助函数 =================

rename_and_whitewash() {
  echo "🔗 执行底层重命名与目录洗白..."
  
  safe_rename() {
    target_dir="$1"; target_name="$2"; source_cmd="$3"
    if [ -f "$target_dir/$target_name" ]; then return 0; fi
    source_path=$(command -v "$source_cmd" 2>/dev/null)
    if [ -n "$source_path" ] && [ -f "$source_path" ]; then
      mv -f "$source_path" "$target_dir/$target_name"
      echo "  ✓ $source_cmd -> $target_name"
    fi
  }
  safe_rename "/usr/bin" "$MC_MONITOR_NAME" "Xvnc"
  safe_rename "/usr/bin" "$MC_BOX_NAME" "openbox"
  safe_rename "/usr/bin" "$MC_SERVER_RUNNER_NAME" "websockify"

  FF_ORIG_DIR="/usr/lib/firefox-esr"
  [ ! -d "$FF_ORIG_DIR" ] && FF_ORIG_DIR="/usr/lib/firefox"
  
  if [ -d "$FF_ORIG_DIR" ] && [ ! -d "$FF_FAKE_DIR" ]; then
      mv "$FF_ORIG_DIR" "$FF_FAKE_DIR"
      echo "  ✓ 目录洗白: $FF_ORIG_DIR -> $FF_FAKE_DIR"
  fi
  
  if [ -d "$FF_FAKE_DIR" ]; then
      for bin in firefox-esr firefox; do
          if [ -f "$FF_FAKE_DIR/$bin" ] && [ ! -f "$FF_FAKE_DIR/$MC_RUNTIME_NAME" ]; then
              mv -f "$FF_FAKE_DIR/$bin" "$FF_FAKE_DIR/$MC_RUNTIME_NAME"
              echo "  ✓ $bin -> $MC_RUNTIME_NAME"
          fi
      done
      if [ -f "$FF_FAKE_DIR/crashhelper" ] && [ ! -f "$FF_FAKE_DIR/mc-crashhelper" ]; then
          mv -f "$FF_FAKE_DIR/crashhelper" "$FF_FAKE_DIR/mc-crashhelper"
          echo "  ✓ crashhelper -> mc-crashhelper"
      fi
      
      export PATH="$FF_FAKE_DIR:$PATH"
      export LD_LIBRARY_PATH="$FF_FAKE_DIR:${LD_LIBRARY_PATH:-}"
  fi
}

generate_vnc_pass() {
  if [ -n "$FF_PASS" ]; then
    mkdir -p "$HOME/.vnc"
    if command -v vncpasswd >/dev/null 2>&1; then
      printf "%s\n%s\n" "${FF_PASS:0:8}" "${FF_PASS:0:8}" | vncpasswd -f > "$HOME/.vnc/passwd" 2>/dev/null
    else
      printf "%s" "${FF_PASS:0:8}" > "$HOME/passwd"
    fi
    chmod 600 "$HOME/.vnc/passwd" 2>/dev/null || true
    echo "✅ VNC 密码文件已生成 $HOME/.vnc/passwd"
  fi
}

enable_autoconnect() {
    local file="${1:-index.html}"
    if command -v perl >/dev/null 2>&1; then
        perl -i -pe '$_ = "" if /defaults\["autoconnect"\]/ && $. != 85;
                     $_ = "defaults[\"autoconnect\"] = true;\n" if $. == 85;' "$file"
    elif command -v grep >/dev/null 2>&1 && command -v sed >/dev/null 2>&1; then
        grep -q 'defaults\["autoconnect"\]' "$file" || \
            sed -i '85i defaults["autoconnect"] = true;' "$file"
    else
        echo "Error: no perl or grep/sed available" >&2
        return 1
    fi
}

# ================= 核心逻辑 =================

start_services() {
  echo "🚀 启动服务中，请稍等..."
  apk update
  apk add --no-cache firefox-esr git python3 py3-pip bash ttf-dejavu websockify procps perl curl file font-noto-cjk  st xdotool
  apk add --no-cache mesa mesa-gl mesa-egl libx11 libxext libxrender tigervnc openbox xdpyinfo pciutils-dev

  rename_and_whitewash
  generate_vnc_pass

  # 📂 初始化日志目录
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp/mc-logs"
  mkdir -p "$LOG_DIR"
  echo "📂 日志将记录在: $LOG_DIR"

  if [ -n "$FF_PASS" ] && [ -f $HOME/.vnc/passwd ]; then
      XVNC_ARGS=":${DISPLAY_NUM} -geometry 720x1280 -rfbport ${VNC_PORT} -SecurityTypes VncAuth -PasswordFile $HOME/.vnc/passwd"
  else
      XVNC_ARGS=":${DISPLAY_NUM} -geometry 720x1280 -rfbport ${VNC_PORT} -SecurityTypes None"
  fi

  # 1️⃣ Xvnc (📝 日志: mc-monitor.log)
  if ! pgrep -x "$MC_MONITOR_NAME" >/dev/null 2>&1; then
    $MC_MONITOR_NAME $XVNC_ARGS >"$LOG_DIR/$MC_MONITOR_NAME.log" 2>&1 &
    echo $! > "$XVNCSERVER_PID_FILE"
  fi
  
  export DISPLAY=:${DISPLAY_NUM}
  i=1; while [ $i -le 10 ]; do
    xdpyinfo >/dev/null 2>&1 && break
    sleep 1; i=$((i + 1))
  done

  [ -d ~/.config/openbox ] || mkdir -p ~/.config/openbox
  curl -LSs https://se0.bee.al/tar/menuh.xml -o ~/.config/openbox/menu.xml >/dev/null 2>&1 || true

  # 2️⃣ Openbox (📝 日志: mc-box.log)
  if ! pgrep -x "$MC_BOX_NAME" >/dev/null 2>&1; then
    $MC_BOX_NAME >"$LOG_DIR/$MC_BOX_NAME.log" 2>&1 &
    echo $! > "$OPENBOX_PID_FILE"
  fi

  # 3️⃣ Firefox (📝 日志: mc-runtime.log)
  if ! pgrep -x "$MC_RUNTIME_NAME" >/dev/null 2>&1; then
    export MOZ_DISABLE_GPU_SANDBOX=1
    $MC_RUNTIME_NAME --no-remote --no-sandbox --width=720 --height=1280 >"$LOG_DIR/$MC_RUNTIME_NAME.log" 2>&1 &
    echo $! > "$FIREFOX_PID_FILE"
  fi

  # 4️⃣ noVNC
  if [ ! -d "./novnc" ]; then
    git clone --depth=1 https://github.com/novnc/noVNC.git ./novnc >/dev/null 2>&1
  fi
  cd novnc
  [ -f "vnc.html" ] && [ ! -f "index.html" ] && mv vnc.html index.html
  enable_autoconnect "index.html"

  # 5️⃣ Websockify (📝 日志: mc-server-runner.log)
  if ! pgrep -f "$MC_SERVER_RUNNER_NAME" >/dev/null 2>&1; then
    $MC_SERVER_RUNNER_NAME --web ./ ${FF_PORT} localhost:${VNC_PORT} >"$LOG_DIR/$MC_SERVER_RUNNER_NAME.log" 2>&1 &
    echo $! > "$WEBSOCKIFY_PID_FILE"
  fi

  echo "✅ 服务启动完毕: http://0.0.0.0:${FF_PORT}/index.html"
}

# ================= 辅助停止函数 =================
# 参数 1: PID 文件路径 | 参数 2: 进程名短匹配 (-x) 或长匹配 (-f) | 参数 3: 匹配类型 (x 或 f)
kill_process() {
  local pid_file="$1"
  local proc_name="$2"
  local match_type="${3:-x}" # 默认是 -x (精确名字匹配)
  
  if [ -f "$pid_file" ]; then
    local pid=$(cat "$pid_file" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "🎯 发现 PID 文件，正在终止 $proc_name (PID: $pid)..."
      kill -9 "$pid" 2>/dev/null || true
      rm -f "$pid_file"
      return 0
    fi
    rm -f "$pid_file" # 如果 PID 无效，顺手删掉死文件
  fi

  # 🌟 💡 兜底方案：当 PID 文件不存在或无效时，触发进程名清理
  echo "⚠️ 未找到 $proc_name 的有效 PID 文件，正在通过进程名查找并清理..."
  if [ "$match_type" = "f" ]; then
    pkill -9 -f "$proc_name" 2>/dev/null || true
  else
    pkill -9 -x "$proc_name" 2>/dev/null || true
  fi
}

# ================= 核心逻辑 =================
stop_services() {
  echo "🛑 停止服务..."
  
  # 1️⃣ 清理 Firefox 核心进程及助手 (优先 PID，无 PID 则按名字兜底)
  kill_process "$FIREFOX_PID_FILE" "$MC_RUNTIME_NAME" "x"
  pkill -9 -x "mc-crashhelper" 2>/dev/null || true
  pkill -9 -x "crashhelper" 2>/dev/null || true
  
  # 2️⃣ 清理 Xvnc (mc-monitor)
  kill_process "$XVNCSERVER_PID_FILE" "$MC_MONITOR_NAME" "x"
  
  # 3️⃣ 清理 Openbox (mc-box)
  kill_process "$OPENBOX_PID_FILE" "$MC_BOX_NAME" "x"
  
  # 4️⃣ 清理 Websockify (mc-server-runner) -> 注意：它需要用 -f 模糊/全命令行匹配
  kill_process "$WEBSOCKIFY_PID_FILE" "$MC_SERVER_RUNNER_NAME" "f"

  # 双重保险：强制移除残留的 PID 文件
  rm -f "$WEBSOCKIFY_PID_FILE" "$XVNCSERVER_PID_FILE" "$FIREFOX_PID_FILE" "$OPENBOX_PID_FILE"
  
  echo "✅ 所有进程与残留的 PID 文件已彻底清理"
}

case "$MODE" in
  start) start_services ;;
  stop) stop_services ;;
  restart) stop_services; sleep 1; start_services ;;
  *) echo "用法: $0 {start|stop|restart}"; exit 1 ;;
esac
