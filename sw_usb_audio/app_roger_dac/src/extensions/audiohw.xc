// Roger DAC v3.4.3.2 — 板级硬件初始化
//
// 开发阶段：复用 XK-AUDIO-216-MC-AB 板载硬件（CS2100 PLL + CS4384 DAC）。
//           板载 CS2100 在 CLK_FIXED 模式下生成 MCLK，模拟 Roger DAC 外部晶振。
//
// 最终 PCB：CCHD-957 晶振 OE 切换 + 继电器延迟接通 + 采样率 LED 显示。
//
// GPIO 分配（最终 PCB）：
//   GPIO_A: 晶振 #1 OE（22.5792 MHz）
//   GPIO_B: 晶振 #2 OE（24.576 MHz）
//   GPIO_C: 继电器控制（Omron G6K-2F）
//   GPIO_D: 采样率编码 bit0 → 74HC138 A0
//   GPIO_E: 采样率编码 bit1 → 74HC138 A1
//   GPIO_F: 采样率编码 bit2 → 74HC138 A2
//
// 晶振切换时序（设计文档 §2.2）：
//   1. 静音 I2S 输出（lib_xua 已完成）
//   2. 禁用当前晶振 OE（→三态）
//   3. 等待 ≥1μs（避免双驱动）
//   4. 使能目标晶振 OE
//   5. 等待晶振输出稳定（~2ms）
//   6. XMOS 重新锁定 MCLK，建立新 BCK/WS
//   7. 恢复 I2S 输出
//
// 启动序列（设计文档 §2.2）：
//   1. GPIO 全部输出 LOW（晶振关闭，继电器断开，LED=44.1k）
//   2. 检测采样率 → 更新 GPIO[F:E:D] 编码
//   3. 使能对应晶振 OE
//   4. USB 枚举完成 → 等待 2 秒（偏置电容充电）
//   5. GPIO_C 拉高 → 继电器接通 RCA 输出 → 无 thump
//   6. 采样率切换时：更新 GPIO[F:E:D] → LED 自动跟随

#include "xua.h"
#include "xua_conf.h"

#if ROGER_DAC_OSC_OE_ENABLE
// ============================================================================
//  最终 PCB：CCHD-957 双晶振 OE + 继电器 + 采样率 LED
// ============================================================================

// TODO: 根据最终原理图确定 port，取消注释
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_osc_oe_44k = ROGER_DAC_OE_44K_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_osc_oe_48k = ROGER_DAC_OE_48K_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_relay      = ROGER_DAC_RELAY_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_led_d      = ROGER_DAC_LED_D_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_led_e      = ROGER_DAC_LED_E_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_led_f      = ROGER_DAC_LED_F_PORT;

static inline int is_44k_family(unsigned samFreq)
{
    return (samFreq % 44100 == 0);
}

// 采样率 → 74HC138 编码 GPIO[F:E:D]
// 000=44.1k, 001=48k, 010=88.2k, 011=96k, 100=176.4k, 101=192k, 111=OFF
static void set_sample_rate_leds(unsigned samFreq)
{
    unsigned d = 0, e = 0, f = 0;

    switch (samFreq) {
    case 44100:  d = 0; e = 0; f = 0; break;  // 000
    case 48000:  d = 1; e = 0; f = 0; break;  // 001
    case 88200:  d = 0; e = 1; f = 0; break;  // 010
    case 96000:  d = 1; e = 1; f = 0; break;  // 011
    case 176400: d = 0; e = 0; f = 1; break;  // 100
    case 192000: d = 1; e = 0; f = 1; break;  // 101
    default:     d = 1; e = 1; f = 1; break;  // 111 = OFF
    }

    // TODO: 取消注释
    // p_led_d <: d;
    // p_led_e <: e;
    // p_led_f <: f;
    (void)d; (void)e; (void)f;
}

void AudioHwInit()
{
    // ---- 启动序列 Step 1: GPIO 全部输出 LOW ----
    // 10kΩ 下拉已保证上电默认 LOW，这里显式设置确保确定状态
    // p_osc_oe_44k <: 0;  // 晶振 #1 关闭
    // p_osc_oe_48k <: 0;  // 晶振 #2 关闭
    // p_relay      <: 0;  // 继电器断开（RCA 隔离）
    // p_led_d      <: 0;  // LED 编码 = 000 (44.1k)
    // p_led_e      <: 0;
    // p_led_f      <: 0;

    // ---- 启动序列 Step 3: 使能默认晶振（44.1k 系列）----
    // p_osc_oe_44k <: 1;

    // ---- 启动序列 Step 4-5: 继电器延迟接通 ----
    // USB 枚举和偏置电容充电需要时间，延迟后接通 RCA 输出
    // delay_milliseconds(ROGER_DAC_RELAY_DELAY_MS);
    // p_relay <: 1;  // 继电器接通 → RCA 输出可用 → 无 thump
}

void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC)
{
    // Roger DAC 无外部 CODEC 需要通过 I2C 配置。
    // 操作：(1) 晶振 OE 切换  (2) 采样率 LED 更新

    // ---- 采样率 LED 更新（每次都执行）----
    set_sample_rate_leds(samFreq);

    // ---- 晶振 OE 切换（仅在切换系列时执行）----
    // static unsigned current_family = 1;  // 1 = 44k family
    // int target_family = is_44k_family(samFreq);
    //
    // if (target_family != current_family) {
    //     // Step 1: 静音由 lib_xua 在调用本函数前已完成
    //     // Step 2: 禁用当前晶振
    //     if (current_family) {
    //         p_osc_oe_44k <: 0;
    //     } else {
    //         p_osc_oe_48k <: 0;
    //     }
    //
    //     // Step 3: 等待 ≥1μs（100MHz tile clock → 100 ticks ≈ 1μs）
    //     delay_microseconds(2);
    //
    //     // Step 4: 使能目标晶振
    //     if (target_family) {
    //         p_osc_oe_44k <: 1;
    //     } else {
    //         p_osc_oe_48k <: 1;
    //     }
    //
    //     // Step 5: 等待晶振稳定（~2ms）
    //     delay_milliseconds(3);
    //
    //     current_family = target_family;
    // }
    //
    // Step 6-7: MCLK 重新锁定和 I2S 恢复由 lib_xua 自动处理
}

#else
// ============================================================================
//  开发板阶段：复用 XK-AUDIO-216-MC-AB 板载硬件
// ============================================================================

#include "app_usb_aud_xk_216_mc.h"
#include <xk_audio_216_mc_ab/board.h>

// CLK_FIXED 模式：CS2100 PLL 生成固定 MCLK，不跟踪 USB SOF
// 这模拟了 Roger DAC 的外部晶振场景（XMOS 从外部接收 MCLK 并分频）
#define CLK_MODE AUD_216_CLK_FIXED
#define PLL_SYNC_FREQ (1000000)

static const xk_audio_216_mc_ab_config_t config = {
    CLK_MODE,
    CODEC_MASTER,
    (USB_SEL_A ? AUD_216_USB_A : AUD_216_USB_B),
    XUA_PCM_FORMAT,
    PLL_SYNC_FREQ
};

void AudioHwInit()
{
    xk_audio_216_mc_ab_AudioHwInit(config);
}

void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC)
{
    xk_audio_216_mc_ab_AudioHwConfig(config, samFreq, mClk, dsdMode,
        sampRes_DAC, sampRes_ADC);
}

#endif // ROGER_DAC_OSC_OE_ENABLE
