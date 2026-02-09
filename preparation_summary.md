# Roger DAC 固件前置准备完成总结

> 基于 `roger_dac_v3.4.2.md` 和 `usb_driver_dev.md`，为 XMOS XU216 固件开发完成的前置工作。

---

## 1. 工具链状态

| 工具 | 状态 | 备注 |
|------|------|------|
| CMake 4.1.2 | OK | |
| Git 2.50.1 | OK | |
| **XTC Tools 15.3** | **未安装** | 需从 https://www.xmos.com/software-tools 下载安装，然后 `source ~/XMOS/XTC/15.3.0/SetEnv` |

---

## 2. 源码仓库

`sw_usb_audio` 已克隆到 `sw_usb_audio/`，包含参考应用和依赖声明。

`lib_xua` 会在 CMake configure 时自动拉取（当前 `deps.cmake` 使用 `develop` 分支，已包含 `XUA_I2S_N_BITS` 支持——该配置项于 lib_xua v3.5.0 引入）。

---

## 3. Roger DAC 固件应用 — `app_roger_dac/`

已在 `sw_usb_audio/` 下创建完整应用目录：

```
app_roger_dac/
  CMakeLists.txt                    ← 构建配置（复用 XK-216-MC 开发板）
  src/
    core/
      xua_conf.h                    ← ★ Roger DAC 核心配置
      xk-audio-216-mc.xn            ← 硬件描述（开发板阶段）
      app_usb_aud_xk_216_mc.h       ← 开发板兼容头
      user_main.h                   ← 空（无额外 tile 任务）
    extensions/
      audiohw.xc                    ← 板级初始化 + 晶振 OE 切换框架
```

---

## 4. `xua_conf.h` 核心配置

| 配置项 | 值 | 作用 |
|--------|-----|------|
| `XUA_I2S_N_BITS` | **16** | 32fs 帧格式（Gate-1 核心） |
| `I2S_CHANS_PER_FRAME` | 2 | 立体声 |
| `MASTER_CLOCK_GENERATED` | 0 | 外部 MCLK |
| `MCLK_441` / `MCLK_48` | 22579200 / 24576000 | CCHD-957 频率 |
| `STREAM_FORMAT_OUTPUT_RESOLUTION` | 16 | USB 传输 16-bit |
| `NUM_USB_CHAN_OUT` / `IN` | 2 / 0 | 仅输出，无输入 |
| `AUDIO_CLASS` | 2 | UAC 2.0 |
| `MIN_FREQ` / `MAX_FREQ` | 44100 / 192000 | 采样率范围 |
| `XUA_DFU_EN` | 1 | 保留 DFU 用于后续固件更新 |
| MIDI / SPDIF / ADAT | 全部 0 | 不需要的功能全部关闭 |

### 32fs 分频验证

BCLK 公式（`lib_xua/src/core/audiohub/xua_audiohub.xc`）：

```c
unsigned numBits = XUA_I2S_N_BITS * I2S_CHANS_PER_FRAME;  // 16 × 2 = 32
divide = mClk / (curSamFreq * numBits);
configure_clock_src_divide(clk_audio_bclk, p_mclk_in, (divide / 2));
```

| 采样率 | 晶振 (MCLK) | divide | BCLK | divide 偶数? |
|--------|-------------|--------|------|-------------|
| 44.1k | 22.5792M | 16 | 1.4112M | Yes |
| 48k | 24.576M | 16 | 1.536M | Yes |
| 88.2k | 22.5792M | 8 | 2.8224M | Yes |
| 96k | 24.576M | 8 | 3.072M | Yes |
| 176.4k | 22.5792M | 4 | 5.6448M | Yes |
| 192k | 24.576M | 4 | 6.144M | Yes |

所有 divide 值均为偶数，满足 xcore 时钟块硬件约束。所有 BCK 频率均在 TDA1543 BCKmax (9.2 MHz) 的 67% 以内。

---

## 5. 晶振 OE 切换

`audiohw.xc` 中已预埋完整切换逻辑框架（注释状态），遵循设计文档 §2.2 的 7 步时序：

1. 静音 I2S 输出
2. 禁用当前晶振 OE（→三态）
3. 等待 ≥1μs（避免双驱动）
4. 使能目标晶振 OE
5. 等待晶振输出稳定（~2ms）
6. XMOS 重新锁定 MCLK，建立新 BCK/WS
7. 恢复 I2S 输出

通过 `ROGER_DAC_OSC_OE_ENABLE` 宏切换两种模式：

| 宏值 | 模式 | 说明 |
|------|------|------|
| 0（当前） | 开发板模式 | 使用 XK-AUDIO-216-MC-AB 板载 CS2100 PLL 生成 MCLK |
| 1（最终 PCB） | 量产模式 | GPIO 控制 CCHD-957 OE 互斥切换 |

---

## 6. 下一步

1. **安装 XTC Tools 15.3** — 编译的前提条件
2. 构建固件：
   ```bash
   source ~/XMOS/XTC/15.3.0/SetEnv
   cd sw_usb_audio/app_roger_dac
   cmake -G "Unix Makefiles" -B build
   xmake -j -C build
   ```
3. 调试运行：`xrun bin/roger_dac.xe`
4. 连接示波器执行 **Gate-1 验证**（32fs 帧格式确认）
