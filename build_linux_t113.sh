#!/bin/bash
# Activate the Klipper Mod Cross Toolchain - sourced by build scripts
cp -rf mcu_configs/linux_config .config

make clean CROSS_PREFIX=/home/song/samba/work/klipper/flashforge/flashforge_ad5m_klipper_mod/build_output/buildroot/variant-guppyscreen-shaketune/host/usr/bin/arm-buildroot-linux-gnueabihf-
make CROSS_PREFIX=/home/song/samba/work/klipper/flashforge/flashforge_ad5m_klipper_mod/build_output/buildroot/variant-guppyscreen-shaketune/host/usr/bin/arm-buildroot-linux-gnueabihf-

make lib V=1 CROSS_PREFIX=/home/song/samba/work/klipper/flashforge/flashforge_ad5m_klipper_mod/build_output/buildroot/variant-guppyscreen-shaketune/host/usr/bin/arm-buildroot-linux-gnueabihf-
