# 上游同步记录：2026-11（81d7055e → 48c25135）

> **来源**：`Klipper3d/klipper` master → 本仓库 `develop`（GitHub Sync fork 合并）
> **范围**：94 个提交（93 实质 + 1 合并），81 个文件，`+2611 / -335` 行
> **冲突**：无（本地自有修改 `pause_resume.py`、`virtual_sdcard.py`、`probe_eddy_ng.py` 上游均未触碰）
> **注意**：`src/stm32/stm32f1.c` 新增约 104 行，合并后引用该文件行号的文档（如
> `F103_Serial_Bootloader_Plan.md` 中的 `stm32f1.c:254-264`）行号已漂移，逻辑未变。

---

## 一、N32G455 专项（7 个提交，AD5M 主控芯片，最重要）

修复该芯片此前时钟/ADC 配置的一系列错误：

| 提交 | 内容 |
|---|---|
| `d94d5704` | 修正 APB 预分频与 flash latency（原配置会导致时序错误） |
| `a9eb1dc9` | 支持 144MHz 主频运行 |
| `1adfb61c` | 修正 48MHz USB 时钟生成 |
| `781a7ce1` | 配置 ADC 时钟 |
| `19ca09d6` | ADC 校准每个块只做一次（原来重复校准） |
| `4bdd32de` | 启用 EX mode |
| `ccbc7d85` | 新增 n32g45x 编译测试（CI 保活） |

另含 `6ea0b349`：stm32f1 新增 PB4/PB5 硬件 PWM 引脚定义。

**涉及文件**：`src/stm32/n32g45x_adc.c`（重构，108 行）、`src/stm32/stm32f1.c`（+104 行）、`src/stm32/hard_pwm.c`、`src/stm32/Kconfig`、`test/configs/n32g45x*.config`。

## 二、探头/调平（约 20 个提交，与涡流探头体系直接相关）

- **temperature_probe**（10+ 个修复）：漂移校准修复、采样计数检查、传感器断联中止、
  异常处理、`METHOD` → `MANUAL_METHOD` 接口变更（见 Config_Changes）、参数转发给 probe；
- **probe_eddy_current**（4 个）：tap 失败时仍输出 Z 值、tap 阈值打印、
  tap 猜测常数更新、移除不可达错误分支；
- **manual_probe**：支持喷嘴探头（nozzle probes）+ 回调异常处理；
- **probe**：喷嘴探头自动禁用 axis_twist_compensation；
- **bed_mesh**：direct 模式 zero_ref 修复、强制校验算法名；
- **axis_twist_compensation**：使用探头的正确坐标、极值点零值修复、变量重命名；
- **load_cell_probe**：慢 ADC 精度提升、G28 Z 越界规避、关闭调试输出。

## 三、新硬件支持

- **CS1237 称重 ADC**：新传感器支持（`load_cell` + 新文件 `src/sensor_cs1237.c`，
  共 6 个提交，含采样/时钟脉冲时序修复）；
- **TMC5262 步进驱动**：新驱动 + TMC 框架增加驱动初始化回调与驱动专属温度换算
  （`klippy/extras/tmc5262.py`）；
- **icm20948** IMU 修复（4 个）：bank 0/2 切换、FIFO 复位与溢出标志清除。

## 四、Klipper 主机端稳定性

- **serialhdl**：MCU 通信超时后正确失败等待中的 ack、shutdown 时不再丢 serialq、
  debug dump 输出格式化；
- **command**：`command_parsef()` 两处越界加固（安全修复）；
- **queuelogger**：无限 rollover 打印规避、裁剪未用日志字段；
- **pid_calibrate**：Ku 公式修正、滞后从 5 降到 2.5；
- **homing**：新增 `homing:home_axes` 事件；
- **trapq/motion_report**：陈旧速度不再上报；
- **Python 3.14 兼容**（2 个）：fork 多进程方式、requirements 更新；
- **garbage_collection**：定义延迟分析器回调。

## 五、其它平台/驱动

- **ar100**（6 个）：改用 serial_irq 处理消息、轮询优化
  （新增 `timer_dispatch_many_polling()`，pru 同步受益）、-O2 构建、
  SERIAL_BAUD 校验、镜像尺寸检查修正；
- **trigger_analog**：AVR 上 `TT_ABS_GE` 修复 + label 后语句修复；
- **linux**：gpiochip 数量上限提升；
- **i2c_software**：SDA 状态切换优化；
- **hd44780**：命令延时可配置；
- **pru**：轮询优化。

## 六、文档/构建（零碎约 10 个）

- G-Codes 文档 M82/M83 说明澄清、TAP 错误说明、FAQ/Load_Cell 修订、内链修复；
- 构建配置嵌入固件 identify data 并通过状态接口暴露——可直接查询 MCU 固件的
  编译配置（`mcu: Log mcu reported kconfig`）；
- kconfiglib savedefconfig.py vendor 进仓库；
- CI workflow 固定 Ubuntu 版本。

---

## 与本项目日常使用关系最大的三块

1. **N32G455 时钟/ADC 修复**——主控稳定性（第一部分）；
2. **探头/涡流系列修复**——`probe_eddy_ng` 基于 eddy 体系（第二部分）；
3. **command_parsef 越界与 serialhdl 超时加固**——通信鲁棒性（第四部分）。
