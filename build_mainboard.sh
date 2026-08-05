#!/bin/bash
# Activate the Klipper Mod Cross Toolchain - sourced by build scripts
cp -rf mcu_configs/mainboard_config .config

make CROSS_PREFIX=/home/song/samba/work/klipper/flashforge/flashforge_ad5m_klipper_mod/build_output/buildroot/variant-guppyscreen-shaketune/host/usr/bin/arm-none-eabi-
make CROSS_PREFIX=/home/song/samba/work/klipper/flashforge/flashforge_ad5m_klipper_mod/build_output/buildroot/variant-guppyscreen-shaketune/host/usr/bin/arm-none-eabi-

cp -rf  out/klipper.hex mcu_configs/mainboard.hex
cp -rf  out/klipper.bin mcu_configs/mainboard.bin

