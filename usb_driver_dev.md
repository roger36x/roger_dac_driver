# Roger DAC USB Driver 开发指南

> 基于 roger_dac_v3.4.2 设计文档，实现 XMOS XU216 固件，输出 32fs I2S 帧格式。

---

## 1. 目标

通过 Gate-1：XMOS 输出真 32fs I2S 信号。

| 指标 | 要求 |
|------|------|
| 帧格式 | 32fs（每 WS 周期 32 个 BCK：左 16 + 右 16） |
| 数据位宽 | 16-bit/声道，每个 BCK 承载有效数据，无填充 |
| I2S 时序 | 标准 I2S：WS 翻转后 1 个 BCK 延迟出 MSB |
| 采样率 | 44.1k / 48k / 88.2k / 96k（默认），176.4k / 192k（验证后启用） |
| 时钟源 | 外部 MCLK（CCHD-957 双晶振：22.5792 MHz / 24.576 MHz） |

### Gate-1 验收标准

- 示波器确认 WS 半周期内恰好 16 个 BCK
- WS 翻转后 1 个 BCK 延迟才出 MSB（标准 I2S 时序）
- 176.4k / 192k 下仍为 32fs（未退回 64fs）

---

## 2. 技术方案

### 2.1 核心发现：lib_xua 原生支持 32fs

XMOS 开源固件库 [lib_xua](https://github.com/xmos/lib_xua) 从 **v3.5.0** 起提供 `XUA_I2S_N_BITS` 配置项。

BCLK 生成公式（`lib_xua/src/core/audiohub/xua_audiohub.xc`）：

```c
unsigned numBits = XUA_I2S_N_BITS * I2S_CHANS_PER_FRAME;
divide = mClk / (curSamFreq * numBits);
configure_clock_src_divide(clk_audio_bclk, p_mclk_in, (divide / 2));
```

设置 `XUA_I2S_N_BITS = 16` + `I2S_CHANS_PER_FRAME = 2`：

```
numBits = 16 × 2 = 32
BCLK = MCLK / divide = fs × 32 = 32fs
```

**无需修改固件源码，只需配置。**

### 2.2 分频验证

| 采样率 | 晶振 (MCLK) | divide | BCLK | BCK/BCKmax(9.2M) | divide 偶数? |
|--------|-------------|--------|------|-------------------|-------------|
| 44.1k | 22.5792M | 16 | 1.4112M | 15% | Yes |
| 48k | 24.576M | 16 | 1.536M | 17% | Yes |
| 88.2k | 22.5792M | 8 | 2.8224M | 31% | Yes |
| 96k | 24.576M | 8 | 3.072M | 33% | Yes |
| 176.4k | 22.5792M | 4 | 5.6448M | 61% | Yes |
| 192k | 24.576M | 4 | 6.144M | 67% | Yes |

所有 divide 值均为偶数，满足 xcore 时钟块硬件约束。
所有 BCK 频率均在 TDA1543 BCKmax (9.2 MHz) 的 67% 以内。

### 2.3 固件配置

在应用的 `xua_conf.h` 中：

```c
// ---- 时钟 ----
#define MASTER_CLOCK_GENERATED              0       // 外部 MCLK（CCHD-957 晶振）
#define MCLK_441                            22579200 // 44.1k 系列晶振
#define MCLK_48                             24576000 // 48k 系列晶振

// ---- I2S 帧格式（Gate-1 核心） ----
#define XUA_I2S_N_BITS                      16      // 16-bit/声道 → BCK = fs × 32 = 32fs
#define I2S_CHANS_PER_FRAME                 2       // 立体声
#define I2S_MODE                            I2S_MODE_I2S

// ---- USB 音频 ----
#define AUDIO_CLASS                         2       // USB Audio Class 2.0
#define STREAM_FORMAT_OUTPUT_RESOLUTION     16      // USB 传输 16-bit
#define NUM_USB_CHAN_OUT                     2       // 2 声道输出
#define NUM_USB_CHAN_IN                      0       // 无输入
#define MAX_FREQ                            192000
#define MIN_FREQ                            44100

// ---- 不需要的功能 ----
#define MIDI                                0
#define SPDIF_TX                            0
#define SPDIF_RX                            0
#define ADAT_TX                             0
#define ADAT_RX                             0
#define XUA_DFU_EN                          1       // 保留 DFU 用于后续固件更新
```

### 2.4 USB 格式与 I2S 格式的关系

两者独立配置：

| 层 | 配置项 | 值 | 说明 |
|----|--------|-----|------|
| USB 描述符 | `HS_STREAM_FORMAT_OUTPUT_x_RESOLUTION_BITS` | 16 | macOS 看到的位深 |
| I2S 总线 | `XUA_I2S_N_BITS` | 16 | 物理线上的位宽 |

当 `XUA_I2S_N_BITS = 16` 时，固件输出内部 32-bit word 的高 16 位到 I2S 总线。

### 2.5 Roger Player 端

无需改动。Roger Player 通过 macOS CoreAudio 与 USB 设备通信：
- 检测到设备为 16-bit → symphonia 解码器输出 16-bit i32 左对齐
- CD 源（16-bit）：bit-perfect
- 24-bit 源：截断发生在软件层（可控、可审计）

---

## 3. 开发环境搭建

### 3.1 硬件

| 组件 | 型号 | 用途 |
|------|------|------|
| 开发板 | XK-AUDIO-216-MC-AB | XU216 多通道音频开发板（含 XTAG 调试器） |
| 示波器 | 任意双通道 | Gate-1 验证 BCK/WS/DATA 波形 |

### 3.2 工具链安装（macOS）

```bash
# 1. 从 https://www.xmos.com/software-tools 下载 XTC Tools 15.3（需注册账号）
#    支持 Intel 和 Apple Silicon

# 2. 解压后设置环境变量
source ~/XMOS/XTC/15.3.0/SetEnv
# 可选：加入 ~/.zshrc 持久化

# 3. 安装依赖
brew install cmake git    # CMake 3.21+, Git 2.25+

# 4. 验证安装
xcc --version
xrun -l                   # 列出已连接的 XTAG 调试器
```

> macOS 安全提示：首次运行可能被 Gatekeeper 拦截，到「系统偏好设置 > 隐私与安全性」中放行，
> 或执行 `xattr -d com.apple.quarantine ~/XMOS/XTC/15.3.0/bin/*`。

### 3.3 源码获取

```bash
git clone --recurse-submodules https://github.com/xmos/sw_usb_audio.git
cd sw_usb_audio
```

仓库结构：

```
sw_usb_audio/
  app_usb_aud_xk_216_mc/          ← XU216 开发板参考应用
    CMakeLists.txt                ← 构建配置，声明 lib_xua 依赖
    core/
      xua_conf.h                  ← ★ 我们修改的配置文件
      XK-AUDIO-216-MC.xn          ← 硬件描述（引脚映射、时钟）
    extensions/
      audiohw.xc                  ← 板级硬件初始化（CODEC I2C 等）
  lib_xua/                        ← USB Audio 核心库（自动拉取）
    api/
      xua_conf_default.h          ← 默认配置（被 xua_conf.h 覆盖）
    src/core/
      audiohub/
        xua_audiohub.xc           ← BCLK 分频计算、端口配置
      clocking/
        clockgen.xc               ← 时钟生成逻辑
```

lib_xua 作为依赖在 CMakeLists.txt 中声明，XCommon CMake 自动从 GitHub 拉取：

```cmake
set(APP_DEPENDENT_MODULES "lib_xua(5.2.0)")
```

---

## 4. 构建 & 烧录

### 4.1 构建

```bash
source ~/XMOS/XTC/15.3.0/SetEnv

cd sw_usb_audio/app_usb_aud_xk_216_mc

# 配置
cmake -G "Unix Makefiles" -B build

# 编译（-j 并行）
xmake -j -C build

# 编译产物在 bin/ 目录下，格式为 .xe
```

### 4.2 调试运行（RAM，断电丢失）

```bash
# 通过 XTAG 加载到 RAM 并运行
xrun bin/<config_name>.xe

# 带 I/O 重定向
xrun --io bin/<config_name>.xe
```

### 4.3 烧录到 Flash（持久化）

```bash
# 写入 SPI Flash
xflash bin/<config_name>.xe

# 指定 boot 分区大小
xflash --boot-partition-size 0x100000 bin/<config_name>.xe
```

### 4.4 USB DFU 更新（后续生产用）

```bash
# 生成 DFU 升级镜像
xflash --factory-version 15.3 --upgrade 1 firmware.xe -o firmware_dfu.bin

# 通过 USB 烧录（需设备已运行支持 DFU 的固件）
sudo xmosdfu --download firmware_dfu.bin
# 或使用开源工具
dfu-util -D firmware_dfu.bin
```

---

## 5. Gate-1 验证步骤

### 5.1 测试配置

1. 将修改后的固件烧录到 XK-AUDIO-216-MC-AB 开发板
2. 通过 USB 连接 macOS，用 Roger Player 播放测试信号
3. 示波器探头接 I2S 输出引脚（BCK / WS / DATA）

### 5.2 验证项

| # | 测试 | 通过标准 |
|---|------|----------|
| 1 | 32fs @ 44.1k/48k | WS 半周期恰好 16 个 BCK |
| 2 | I2S 时序 | WS 翻转后 1 个 BCK 延迟出 MSB |
| 3 | 32fs @ 88.2k/96k | 同上，BCK 频率翻倍但仍为 32fs |
| 4 | 32fs @ 176.4k/192k | 确认未退回 64fs |
| 5 | DATA 有效性 | 每个 BCK 周期 DATA 都有有效电平（无空闲时钟） |
| 6 | 长时间稳定性 | 4 小时无异常 |

### 5.3 降级方案

如果 32fs 不可行（固件不支持或验证失败）：

1. 回退到 64fs（`XUA_I2S_N_BITS = 32`）
2. 最高采样率硬限制为 96k（64fs × 96k = 6.144 MHz, 67% of BCKmax）
3. 必须执行 32fs vs 64fs 对照实验（见设计文档 3.6 节）

---

## 6. 关键源文件索引

| 文件 | 位置 | 作用 |
|------|------|------|
| `xua_conf.h` | `app/core/` | 应用配置覆盖（**我们改这个**） |
| `xua_conf_default.h` | `lib_xua/api/` | 默认配置参考 |
| `xua_audiohub.xc` | `lib_xua/src/core/audiohub/` | BCLK 分频计算、I2S 端口配置 |
| `clockgen.xc` | `lib_xua/src/core/clocking/` | 时钟生成 |
| `audiohub_initport.xc` | `lib_xua/src/core/audiohub/` | 端口初始化（master/slave） |

---

## 7. 参考资源

- [lib_xua GitHub](https://github.com/xmos/lib_xua)
- [sw_usb_audio GitHub](https://github.com/xmos/sw_usb_audio)
- [XTC Tools 下载](https://www.xmos.com/software-tools)
- [sw_usb_audio 配置参考](https://www.xmos.com/documentation/XM-008854-UG/html/doc/rst/api_xua_conf.html)
- [lib_xua 文档 (v5.2.0)](https://www.xmos.com/documentation/XM-012296-UG/pdf/lib_xua_v5.2.0.pdf)
- [XCommon CMake](https://github.com/xmos/xcommon_cmake)
- [AN02019: USB Audio DFU](https://www.xmos.com/documentation/XM-015226-AN/html/)
- [XK-AUDIO-216-MC-AB 硬件手册](https://www.xmos.com/documentation/XM-015142-UG/html/doc/rst/xk_audio_216_mc_ab/hw_216_mc.html)
