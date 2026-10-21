#!/bin/bash
# ============================================================================
# build_linux_rv1106.sh —— 编译 Klipper Linux MCU（RV1106）+ 部署 klippy 到板端
#
# 用法:
#   ./build_linux_rv1106.sh            # 增量编译（固件 + klippy c_helper.so，默认）
#   ./build_linux_rv1106.sh all        # 同上
#   ./build_linux_rv1106.sh check      # 只检查工具链、配置与产物，不编译
#   ./build_linux_rv1106.sh clean      # 清理 out/ 与 klippy/chelper/c_helper.so
#   ./build_linux_rv1106.sh install    # 复制 klippy .py 进 SDK overlay（随 rootfs 打包）
#   ./build_linux_rv1106.sh deploy     # 部署 klippy .py 到板端设备（192.168.0.30）并重启 klippy
#
# 可选环境变量:
#   TC_PREFIX=...    交叉编译器前缀（含末尾 '-'），默认 arm-rockchip830-linux-uclibcgnueabihf-
#   CONFIG=...       使用的 MCU 配置，默认 mcu_configs/linux_config
#   FORCE_CLEAN=1    编译前强制 make clean（默认仅在板型切换时自动清理）
#   INSTALL_DIR=...  install 目标目录，默认 $SDK_ROOT/.../overlay-gt-buildroot-app/opt/klipper
#   SDK_ROOT=...     RV1106 SDK 根（仅用于 install 默认 overlay），默认
#                    /home/song/samba/work/rv1106/rk-sdk/RV1106_IPC_SDK
#   DEVICE_IP=...    deploy 目标设备 IP，默认 192.168.0.30
#   DEVICE_USER=...  deploy 登录用户，默认 root
#
# 说明:
#   原脚本每次无条件 make clean + 全量重编。本脚本改为增量编译：仅当
#   .config 内容变化或 out/ 的目标板型与配置不一致时才清理，其余情况复用
#   out/ 里的目标文件。需要全量重编请先 ./build_linux_rv1106.sh clean。
#
#   产物:
#     out/klipper.elf                  Linux MCU 固件
#     klippy/chelper/c_helper.so       klippy 的 C 加速库（RV1106 目标架构）
#
#   install: 复制 klippy .py + c_helper.so 进 buildroot overlay 源目录（随 rootfs 打包，
#            烧录生效，不含 out/klipper.elf）。
#   deploy:  连通性检查 -> 空闲检查（打印中禁止部署）->
#            tar 同步 klippy 源码 + c_helper.so -> 清除 __pycache__ ->
#            /opt/S20klipper restart -> 启动与日志校验（不下发 out/klipper.elf）。
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

TC_PREFIX="${TC_PREFIX:-arm-rockchip830-linux-uclibcgnueabihf-}"
CONFIG="${CONFIG:-mcu_configs/linux_config}"

ELF="$SCRIPT_DIR/out/klipper.elf"
CHELPER="$SCRIPT_DIR/klippy/chelper/c_helper.so"

# install 目标：buildroot overlay 源目录（随 rootfs 一起打包进镜像）
SDK_ROOT="${SDK_ROOT:-/home/song/samba/work/rv1106/rk-sdk/RV1106_IPC_SDK}"
OVERLAY_APP="$SDK_ROOT/project/cfg/BoardConfig_IPC/overlay/overlay-gt-buildroot-app"
INSTALL_DIR="${INSTALL_DIR:-$OVERLAY_APP/opt/klipper}"

# deploy 目标设备（板端）
DEVICE_IP="${DEVICE_IP:-192.168.0.30}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_KLIPPY_DIR="/opt/klipper/klippy"
# ControlMaster 复用连接：整个 deploy 只需输一次 ssh 密码
SSH_OPTS=(-o ControlMaster=auto -o ControlPath="/tmp/ssh-klipper-${DEVICE_USER}@${DEVICE_IP}" \
          -o ControlPersist=120 -o ConnectTimeout=5)

device_sh() { ssh "${SSH_OPTS[@]}" "$DEVICE_USER@$DEVICE_IP" "$@"; }

msg() { echo "==> $*"; }
err() { echo "!!  $*" >&2; }
die() { err "$*"; exit 1; }

# ---------------------------------------------------------------- 环境检查
check_env() {
    command -v "${TC_PREFIX}gcc" >/dev/null 2>&1 || die "找不到交叉编译器: ${TC_PREFIX}gcc
    请确认 TC_PREFIX 正确（或在 PATH 中），默认 /opt/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin/"
    [ -f "$CONFIG" ] || die "找不到 MCU 配置: $CONFIG"
    echo "  工具链 : $(command -v "${TC_PREFIX}gcc")"
    echo "  配置   : $CONFIG"
    echo "  编译器 : $("${TC_PREFIX}gcc" --version | head -1)"
}

# 读取配置文件里的目标板型
config_board() {
    sed -n 's/^CONFIG_BOARD_DIRECTORY="\(.*\)"/\1/p' "$1" | head -1
}

# ---------------------------------------------------------------- 配置同步
# 仅在 .config 内容与源配置不同时拷贝（避免 cp 刷新 mtime 触发全量重编）；
# 板型切换（如 eboard -> linux）时必须先 make clean，否则 out/ 里的目标文件会串用。
sync_config() {
    local new_board cur_board=""
    new_board="$(config_board "$CONFIG")"
    [ -n "$new_board" ] || die "配置中缺少 CONFIG_BOARD_DIRECTORY: $CONFIG"

    [ -L out/board ] && cur_board="$(basename "$(readlink out/board)")"
    if [ -n "$cur_board" ] && [ "$cur_board" != "$new_board" ]; then
        msg "板型切换 $cur_board -> $new_board，清理 out/"
        make clean CROSS_PREFIX="$TC_PREFIX"
    fi

    if [ -f .config ] && cmp -s "$CONFIG" .config; then
        msg ".config 已与 $CONFIG 一致，跳过拷贝"
    else
        cp -f "$CONFIG" .config
        msg ".config <- $CONFIG"
    fi
}

# ---------------------------------------------------------------- 编译
build() {
    local t_fw=0 t_lib=0

    check_env

    if [ "${FORCE_CLEAN:-0}" = "1" ]; then
        msg "FORCE_CLEAN=1，清理 out/"
        make clean CROSS_PREFIX="$TC_PREFIX"
    fi
    sync_config

    msg "编译 Linux MCU 固件（out/klipper.elf）"
    make CROSS_PREFIX="$TC_PREFIX"
    t_fw=$SECONDS

    msg "编译 klippy c_helper.so"
    make lib V=1 CROSS_PREFIX="$TC_PREFIX"
    t_lib=$((SECONDS - t_fw))

    [ -f "$ELF" ] || die "编译未产出 $ELF"
    [ -f "$CHELPER" ] || die "编译未产出 $CHELPER"
    echo "  -> $ELF  ($(du -h "$ELF" | cut -f1))"
    echo "  -> $CHELPER  ($(du -h "$CHELPER" | cut -f1))"
    echo "==> 计时: 固件=${t_fw}s lib=${t_lib}s 合计=${SECONDS}s"
}

# ---------------------------------------------------------------- 安装
# 复制 klippy Python 源码 + c_helper.so（make lib 产出的 ARM 版）进 buildroot
# overlay 源目录，随 rootfs 一起打包进镜像。不含 klipper.elf（固件层另行处理）。
cmd_install() {
    [ -d "$SCRIPT_DIR/klippy" ] || die "缺少 klippy 源码目录: $SCRIPT_DIR/klippy"
    [ -f "$CHELPER" ] || die "缺少产物: $CHELPER
    请先执行 $0 完成编译"

    local parent
    parent="$(dirname "$INSTALL_DIR")"
    [ -d "$parent" ] || die "overlay 父目录不存在: $parent
    请确认 SDK 结构（或设置 INSTALL_DIR / SDK_ROOT）"

    mkdir -p "$INSTALL_DIR/klippy"
    tar -C "$SCRIPT_DIR/klippy" -cf - \
        --exclude='__pycache__' --exclude='*.pyc' . \
        | tar -C "$INSTALL_DIR/klippy" -xf -

    msg "已复制到 overlay: $INSTALL_DIR/klippy/（含 c_helper.so，不含 __pycache__）"
    echo "  下一步: 重新打包 rootfs，烧录后板端即为 /opt/klipper/klippy/"
}

# ---------------------------------------------------------------- 部署
# 部署 klippy Python 源码 + c_helper.so 到板端设备（不下发 out/klipper.elf）。
cmd_deploy() {
    [ -d "$SCRIPT_DIR/klippy" ] || die "缺少 klippy 源码目录: $SCRIPT_DIR/klippy"

    msg "连通性检查 $DEVICE_USER@$DEVICE_IP"
    device_sh true || die "无法连接设备 $DEVICE_IP
    请确认网络可达与 ssh 密码（ControlMaster 已开启，本次运行只需输一次）"

    # 部署安全红线：打印/暂停中禁止部署（AGENTS.md）
    # 在设备侧查 localhost:7125（moonraker 信任本机；宿主机直连可能被拒）
    local state
    state="$(device_sh "curl -s --max-time 5 'http://localhost:7125/printer/objects/query?print_stats' 2>/dev/null \
        || wget -q -O - -T 5 'http://localhost:7125/printer/objects/query?print_stats' 2>/dev/null" \
        | python3 -c 'import sys,json;print(json.load(sys.stdin)["status"]["print_stats"]["state"])' 2>/dev/null \
        || echo unknown)"
    case "$state" in
        printing|paused)
            die "设备正在打印（print_stats.state=$state），禁止部署。请等打印结束或先取消"
            ;;
        unknown)
            err "无法从 moonraker 获取打印状态（可能未启动），请自行确认设备空闲"
            ;;
        *)
            echo "  打印状态: $state（空闲，允许部署）"
            ;;
    esac

    msg "同步 klippy 源码 + c_helper.so -> $DEVICE_IP:$DEVICE_KLIPPY_DIR/"
    tar -C "$SCRIPT_DIR/klippy" -cf - \
        --exclude='__pycache__' --exclude='*.pyc' . \
        | ssh "${SSH_OPTS[@]}" "$DEVICE_USER@$DEVICE_IP" "tar -C $DEVICE_KLIPPY_DIR -xf -" \
        || die "源码同步失败（检查设备端 tar 是否可用）"

    msg "清除设备端 __pycache__/*.pyc（否则加载旧字节码）"
    device_sh "find /opt/klipper -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null; \
        find /opt/klipper -name '*.pyc' -delete 2>/dev/null; true"

    msg "重启 klippy (/opt/S20klipper restart)"
    device_sh "/opt/S20klipper restart" || die "重启失败，请手动执行 /opt/S20klipper restart"

    msg "等待 klippy 启动"
    local i running=""
    for i in 1 2 3 4 5 6; do
        sleep 3
        running="$(device_sh "pgrep -f klippy.py >/dev/null && echo yes || echo no" 2>/dev/null || echo no)"
        [ "$running" = "yes" ] && break
    done
    if [ "$running" = "yes" ]; then
        echo "  klippy 进程已运行"
    else
        err "未检测到 klippy 进程，请检查日志: ssh $DEVICE_USER@$DEVICE_IP tail -50 /root/printer_data/logs/klipper.log"
        return 1
    fi

    local errors
    errors="$(device_sh "sleep 2; tail -50 /root/printer_data/logs/klipper.log 2>/dev/null | grep -iE 'error|traceback|import|exception' | head -5" || true)"
    if [ -n "$errors" ]; then
        err "日志中发现疑似错误:"
        echo "$errors"
    else
        echo "  日志无 import/error"
    fi

    msg "部署完成: $DEVICE_IP:$DEVICE_KLIPPY_DIR/"
}

# ---------------------------------------------------------------- 清理
cmd_clean() {
    make clean CROSS_PREFIX="$TC_PREFIX"
    rm -f "$CHELPER"
    msg "已清理: out/ + klippy/chelper/c_helper.so"
}

# ---------------------------------------------------------------- 检查
cmd_check() {
    check_env
    local new_board
    new_board="$(config_board "$CONFIG")"
    echo "  目标板型: $new_board"
    if [ -f .config ]; then
        echo "  当前 .config 板型: $(config_board .config)"
    else
        echo "  当前 .config: 不存在"
    fi

    local a
    for a in "$ELF" "$CHELPER"; do
        if [ -f "$a" ]; then
            echo "  产物存在: $a ($(du -h "$a" | cut -f1))"
        else
            echo "  产物缺失: $a"
        fi
    done

    [ -f "$ELF" ] && [ -f "$CHELPER" ] && echo "环境就绪。" || echo "需先执行 $0 编译。"
}

# ---------------------------------------------------------------- 主流程
cmd="${1:-all}"
case "$cmd" in
    all|"")  build ;;
    check)   cmd_check ;;
    clean)   cmd_clean ;;
    install) cmd_install ;;
    deploy)  cmd_deploy ;;
    *)
        echo "用法: $0 [all|check|clean|install|deploy]"
        exit 1
        ;;
esac
