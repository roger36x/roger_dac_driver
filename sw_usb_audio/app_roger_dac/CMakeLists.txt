cmake_minimum_required(VERSION 3.21)
include($ENV{XMOS_CMAKE_PATH}/xcommon.cmake)
project(app_roger_dac)

# 开发阶段复用 XK-AUDIO-216-MC-AB 开发板的硬件描述文件。
# 最终 Roger DAC PCB 需要替换为自定义 .xn 文件。
set(APP_HW_TARGET xk-audio-216-mc.xn)

include(${CMAKE_CURRENT_LIST_DIR}/../deps.cmake)

set(APP_PCA_ENABLE ON)

# Roger DAC 构建配置
# 命名: 2A = UAC2.0 Async, Mi = Master(内部分频), 2o = 2ch out, 0i = 0ch in
set(APP_COMPILER_FLAGS_roger_dac -O3
                                 -report
                                 -lquadflash
                                 -g
                                 -Wall
                                 -fxscope
                                 -DBOARD_SUPPORT_BOARD=XK_AUDIO_216_MC_AB)

set(APP_INCLUDES src src/core src/extensions)
set(XMOS_SANDBOX_DIR ${CMAKE_CURRENT_LIST_DIR}/../..)

XMOS_REGISTER_APP()
