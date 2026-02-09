// Roger DAC v3.4.2 — 板级硬件初始化
//
// 开发阶段：复用 XK-AUDIO-216-MC-AB 板载硬件（CS2100 PLL + CS4384 DAC）。
//           板载 CS2100 在 CLK_FIXED 模式下生成 MCLK，模拟 Roger DAC 外部晶振。
//
// 最终 PCB：替换为 CCHD-957 晶振 OE 切换逻辑。
//           AudioHwConfig() 中根据采样率系列切换 22.5792/24.576 MHz 晶振。
//
// 切换时序（设计文档 §2.2）：
//   1. 静音 I2S 输出
//   2. 禁用当前晶振 OE（→三态）
//   3. 等待 ≥1μs（避免双驱动）
//   4. 使能目标晶振 OE
//   5. 等待晶振输出稳定（~2ms）
//   6. XMOS 重新锁定 MCLK，建立新 BCK/WS
//   7. 恢复 I2S 输出

#include "xua.h"
#include "xua_conf.h"

#if ROGER_DAC_OSC_OE_ENABLE
// ============================================================================
//  最终 PCB：CCHD-957 双晶振 OE 控制
// ============================================================================

// TODO: 根据最终原理图确定 port
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_osc_oe_44k = ROGER_DAC_OE_44K_PORT;
// on tile[XUA_AUDIO_IO_TILE_NUM]: out port p_osc_oe_48k = ROGER_DAC_OE_48K_PORT;

static inline int is_44k_family(unsigned samFreq)
{
    return (samFreq % 44100 == 0);
}

void AudioHwInit()
{
    // 上电安全：GPIO 初始化为低电平（10kΩ 下拉已保证 OE=LOW）
    // p_osc_oe_44k <: 0;
    // p_osc_oe_48k <: 0;

    // 默认使能 44.1k 系列晶振（设备初始采样率通常为 44.1k）
    // p_osc_oe_44k <: 1;
}

void AudioHwConfig(unsigned samFreq, unsigned mClk, unsigned dsdMode,
    unsigned sampRes_DAC, unsigned sampRes_ADC)
{
    // Roger DAC 无外部 CODEC 需要通过 I2C 配置。
    // 唯一操作：根据采样率系列切换晶振 OE。

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
