#!/bin/bash
# Activate the Klipper Mod Cross Toolchain - sourced by build scripts
cp -rf mcu_configs/linux_config .config

make clean CROSS_PREFIX=arm-rockchip830-linux-uclibcgnueabihf-
make CROSS_PREFIX=arm-rockchip830-linux-uclibcgnueabihf-

make lib V=1 CROSS_PREFIX=arm-rockchip830-linux-uclibcgnueabihf-
