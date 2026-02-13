// Roger DAC v3.4.3.2 — XMOS XU216 固件配置
// 基于 sw_usb_audio 参考设计，针对 Roger DAC 硬件定制。
//
// 核心目标：32fs I2S 帧格式输出 → TDA1543 ×4（2并联/声道）
// 时钟：外部 CCHD-957 双晶振，OE 互斥切换
// 继电器：Omron G6K-2F，上电延迟 2 秒接通（防 thump）
// 采样率 LED：74HC138 译码驱动 6 颗 LED
//
// 参考：roger_dac_v3.4.3.2.md §4.3, usb_driver_dev.md §2.3
#ifndef _XUA_CONF_H_
#define _XUA_CONF_H_

#ifndef __ASSEMBLER__
#include <platform.h>
#endif
#include "../../../shared/version.h"

// ============================================================================
//  时钟配置
// ============================================================================

// 外部 MCLK（CCHD-957 晶振自由振荡，非 XMOS 内部 PLL 生成）
#define MASTER_CLOCK_GENERATED              0

// CCHD-957 双晶振频率（Hz）
// 22.5792 MHz = 512 × 44100  → 44.1k / 88.2k / 176.4k 系列
// 24.576  MHz = 512 × 48000  → 48k / 96k / 192k 系列
#define MCLK_441                            (22579200)
#define MCLK_48                             (24576000)

// ============================================================================
//  I2S 帧格式 — Gate-1 核心
// ============================================================================

// 16-bit/声道 → BCK = fs × (16 × 2) = fs × 32 = 32fs
// lib_xua BCLK 公式：numBits = XUA_I2S_N_BITS × I2S_CHANS_PER_FRAME
//                     divide  = MCLK / (fs × numBits)
// 例：44.1k → divide = 22579200 / (44100 × 32) = 16（偶数，满足 xcore 约束）
#define XUA_I2S_N_BITS                      16
#define I2S_CHANS_PER_FRAME                 2

// 标准 I2S 模式（WS 翻转后 1 BCK 延迟出 MSB）
// TDA1543 原生 I2S 格式，BCK 下降沿锁存 DATA
#ifndef XUA_PCM_FORMAT
#define XUA_PCM_FORMAT                      XUA_PCM_FORMAT_I2S
#endif

// ============================================================================
//  USB 音频
// ============================================================================

// USB Audio Class 2.0（macOS 原生支持，异步模式）
#define AUDIO_CLASS                         2

// USB 传输 16-bit（与 I2S 物理位宽一致）
#ifndef STREAM_FORMAT_OUTPUT_RESOLUTION
#define STREAM_FORMAT_OUTPUT_RESOLUTION     16
#endif

// 2 声道立体声输出，无输入
#define I2S_CHANS_DAC                       2
#define I2S_CHANS_ADC                       0
#define NUM_USB_CHAN_OUT                     2
#define NUM_USB_CHAN_IN                      0

// 采样率范围
#define MIN_FREQ                            44100
#define MAX_FREQ                            192000

// ============================================================================
//  不需要的功能——全部关闭
// ============================================================================

#define MIDI                                0
#define XUA_SPDIF_TX_EN                     0
#define XUA_SPDIF_RX_EN                     0
#define XUA_ADAT_TX_EN                      0
#define XUA_ADAT_RX_EN                      0
#define MIXER                               0
#define MAX_MIX_COUNT                       0
#define HID_CONTROLS                        0

// DFU 保留——用于后续固件更新
#define XUA_DFU_EN                          1

// ============================================================================
//  电源模式
// ============================================================================

// Roger DAC 电池供电，USB 端为自供电设备
#define XUA_POWERMODE                       XUA_POWERMODE_SELF

// ============================================================================
//  USB 描述符
// ============================================================================

// TODO: 正式生产前申请自有 VID/PID
// 开发阶段暂用 XMOS 参考设计 ID
#define VENDOR_ID                           (0x20B1)
#define PID_AUDIO_2                         (0x000E)
#define PID_AUDIO_1                         (0x000F)

#define PRODUCT_STR_A2                      "Roger DAC v3.4.3.2 (UAC2.0)"
#define PRODUCT_STR_A1                      "Roger DAC v3.4.3.2 (UAC1.0)"

// ============================================================================
//  Tile 分配（与 XK-AUDIO-216-MC-AB 开发板一致）
// ============================================================================

#define XUA_AUDIO_IO_TILE_NUM               0
#define XUA_PLL_REF_TILE_NUM                0
#define XUA_XUD_TILE_NUM                    1
#define XUA_MIDI_TILE_NUM                   1

// ============================================================================
//  晶振 OE GPIO 引脚定义
// ============================================================================
//
// Roger DAC 最终 PCB：
//   GPIO_A → CCHD-957 #1 (22.5792 MHz) OE
//   GPIO_B → CCHD-957 #2 (24.576 MHz)  OE
//   互斥控制，10kΩ 下拉保证上电默认关闭
//
// 开发板阶段：XK-AUDIO-216-MC-AB 板载 CS2100 PLL 生成 MCLK，
//             无需 GPIO OE 控制。此宏仅在最终 PCB 上启用。
#define ROGER_DAC_OSC_OE_ENABLE             0

// 当 ROGER_DAC_OSC_OE_ENABLE = 1 时，以下引脚定义生效
// 具体 port 需根据最终 PCB 原理图确定
//
// GPIO_A: 晶振 #1 OE（22.5792 MHz），10kΩ 下拉
// GPIO_B: 晶振 #2 OE（24.576 MHz），10kΩ 下拉
// #define ROGER_DAC_OE_44K_PORT            XS1_PORT_1x
// #define ROGER_DAC_OE_48K_PORT            XS1_PORT_1x
//
// GPIO_C: 继电器控制（Omron G6K-2F，NPN 驱动），10kΩ 下拉
//   上电默认 LOW（断开），USB 枚举完成后延迟 2 秒拉高
// #define ROGER_DAC_RELAY_PORT             XS1_PORT_1x
#define ROGER_DAC_RELAY_DELAY_MS            2000
//
// GPIO_D/E/F: 采样率 LED 编码 → 74HC138 译码器
//   GPIO[F:E:D] 编码表：
//     000 = 44.1k,  001 = 48k,   010 = 88.2k
//     011 = 96k,    100 = 176.4k, 101 = 192k
//     111 = 全灭（OFF 状态）
// #define ROGER_DAC_LED_D_PORT             XS1_PORT_1x  // bit0 (A0)
// #define ROGER_DAC_LED_E_PORT             XS1_PORT_1x  // bit1 (A1)
// #define ROGER_DAC_LED_F_PORT             XS1_PORT_1x  // bit2 (A2)

#include "user_main.h"

#endif // _XUA_CONF_H_
