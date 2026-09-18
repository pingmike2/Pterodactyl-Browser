#!/bin/sh

export HISTFILE=/dev/null
WORKDIR="alpine"
init_env() {
    # 自动识别架构
    ARCH=$(uname -m)
    if [ -n "$ALPINEDIR" ]; then
        WORKDIR="$ALPINEDIR"
    fi
    BIN="$WORKDIR/proot"

    echo "📦 检测架构: $ARCH"

    # 判断是否已初始化
    if [ -f "$BIN" ]; then
        echo "✅ 目录 $WORKDIR 已存在，跳过初始化步骤。"
        cd "$WORKDIR"
        return 0
    fi

    mkdir -p "$WORKDIR" && cd "$WORKDIR"
    mkdir -p rootfs

    # 下载 proot
    case "$ARCH" in
        x86_64)
            PROOT_URL="https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-x86_64-static"
            ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.0-x86_64.tar.gz"
            ;;
        aarch64)
            PROOT_URL="https://github.com/proot-me/proot/releases/download/v5.3.0/proot-v5.3.0-aarch64-static"
            ROOTFS_URL="https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/aarch64/alpine-minirootfs-3.22.0-aarch64.tar.gz"
            ;;
        *)
            echo "❌ 不支持的架构: $ARCH"
            return 1
            ;;
    esac

    echo "🔽 下载 proot 和 rootfs..."
    curl -sL --max-time 10 "$PROOT_URL" -o proot && chmod +x proot

    if ! curl -sL --max-time 10 "$ROOTFS_URL" | tar -xz -C rootfs || [ ! -f "proot" ]; then
        echo "⚠️ 主源下载失败"

        if [ "$ARCH" = "x86_64" ]; then
            echo "🧭 尝试使用备用源..."
            curl -sL --max-time 30 https://se0.bee.al/tar/alpine322.tar.gz -o alpine.tar.gz
            tar -xzvf alpine.tar.gz
            rm -f alpine.tar.gz
        else
            echo "❌ 当前架构无备用源，初始化失败"
            return 1
        fi
    fi
    echo "export HISTFILE=/dev/null" >> ./rootfs/root/.profile
    echo "✅ 初始化完成"
}
init_env

# 如果 PROOT_DIR 没有定义，就设置并写入 ~/.bashrc
if [ -z "$PROOT_DIR" ]; then
  export PROOT_DIR="$(pwd)"
  # 如果 ~/.bashrc 不存在就先创建
  [ -f ~/.bashrc ] || touch ~/.bashrc
  # 如果文件里没有 PROOT_DIR 配置，就追加一行
  grep -q 'PROOT_DIR=' ~/.bashrc || echo "export PROOT_DIR=\"$(pwd)\"" >> ~/.bashrc
fi


# 如果 PROOT_TMP_DIR 没有定义，就设置并写入 ~/.bashrc
if [ -z "$PROOT_TMP_DIR" ]; then
  export PROOT_TMP_DIR="$(pwd)/tmps"
  mkdir -p "$PROOT_TMP_DIR"
  [ -f ~/.bashrc ] || touch ~/.bashrc
  grep -q 'PROOT_TMP_DIR' ~/.bashrc || echo "export PROOT_TMP_DIR=\"$(pwd)/tmps\"" >> ~/.bashrc
fi

if [ ! -d "$PROOT_TMP_DIR" ]; then
  mkdir -p "$PROOT_TMP_DIR"
fi

if [ ! -f "$PROOT_TMP_DIR/hosts" ]; then
    cp /etc/hosts "$PROOT_TMP_DIR/hosts"
    chmod +w "$PROOT_TMP_DIR/hosts"
    echo "已复制 /etc/hosts 到 $PROOT_TMP_DIR/hosts 并赋予写权限"
else
    echo "$PROOT_TMP_DIR/hosts 已存在，跳过操作"
fi

if [ -f "./proot" ]; then
    echo "发现 proot 文件，切换到上一级目录..."
    cd ..
fi
# PROOT_STARTED=1 ./proot -S ./rootfs -b /proc -b /sys -w "$PROOT_DIR" --cwd=/root  \
# -b /etc/resolv.conf:/etc/resolv.conf \
# -b /$PROOT_TMP_DIR/hosts:/etc/hosts