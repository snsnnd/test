#include "inmp441_sensor.h"
#include <stddef.h>
#include <string.h>
#include "i2s.h"
#include "hal_sio.h"
#include "pinctrl.h"
#include "platform_core.h"

#define INMP441_I2S_BUS             SIO_BUS_0
#define INMP441_DIV_NUMBER          32
#define INMP441_CHANNEL_NUMBER      2
#define INMP441_I2S_SCLK_PIN        GPIO_10
#define INMP441_I2S_WS_PIN          GPIO_00
#define INMP441_I2S_DI_PIN          GPIO_12
#define INMP441_I2S_PIN_MODE        PIN_MODE_4

static uint8_t g_inmp441_ready = 0;
static volatile uint32_t g_inmp441_level = 0;
static int16_t g_inmp441_audio_ring[INMP441_AUDIO_WINDOW_SAMPLES] = { 0 };
static volatile uint32_t g_inmp441_audio_write_index = 0;
static volatile uint32_t g_inmp441_audio_total_samples = 0;

static uint32_t INMP441_Abs32(int32_t value)
{
    return (value < 0) ? (uint32_t)(-(int64_t)value) : (uint32_t)value;
}

static int16_t INMP441_ConvertSample(uint32_t raw_sample)
{
    return (int16_t)(((int32_t)raw_sample) >> 8);
}

static uint32_t INMP441_MaxU32(uint32_t left, uint32_t right)
{
    return (left > right) ? left : right;
}

static void INMP441_PinMux_Init(void)
{
    /*
     * 根据当前项目只采集麦克风输入，保留 SCLK/WS/DI 三根必要线，
     * 不再额外占用 GPIO_09 对应的 I2S_DO 复用脚，降低对保留硬件配置脚的影响。
     */
    uapi_pin_set_mode(INMP441_I2S_SCLK_PIN, INMP441_I2S_PIN_MODE);
    uapi_pin_set_mode(INMP441_I2S_WS_PIN, INMP441_I2S_PIN_MODE);
    uapi_pin_set_mode(INMP441_I2S_DI_PIN, INMP441_I2S_PIN_MODE);
    uapi_pin_set_pull(INMP441_I2S_WS_PIN, PIN_PULL_TYPE_DISABLE);
    uapi_pin_set_pull(INMP441_I2S_DI_PIN, PIN_PULL_TYPE_DISABLE);
}

static void INMP441_OnData(uint32_t *left_buff, uint32_t *right_buff, uint32_t length)
{
    uint64_t total_level = 0;
    uint32_t write_index = g_inmp441_audio_write_index;

    if ((left_buff == NULL) || (right_buff == NULL) || (length == 0)) {
        return;
    }

    for (uint32_t i = 0; i < length; i++) {
        int32_t mono_sample = (int32_t)left_buff[i];
        uint32_t left_level = INMP441_Abs32((int32_t)left_buff[i]);
        uint32_t right_level = INMP441_Abs32((int32_t)right_buff[i]);

        if ((mono_sample == 0) && (right_buff[i] != 0)) {
            mono_sample = (int32_t)right_buff[i];
        }

        g_inmp441_audio_ring[write_index] = INMP441_ConvertSample((uint32_t)mono_sample);
        write_index++;
        if (write_index >= INMP441_AUDIO_WINDOW_SAMPLES) {
            write_index = 0;
        }

        total_level += INMP441_MaxU32(left_level, right_level);
    }

    g_inmp441_audio_write_index = write_index;
    g_inmp441_audio_total_samples += length;
    g_inmp441_level = (uint32_t)(total_level / length);
}

uint8_t INMP441_Sensor_IsReady(void)
{
    return g_inmp441_ready;
}

errcode_t INMP441_Sensor_Init(void)
{
    i2s_config_t config = {
        .drive_mode = MASTER,
        .transfer_mode = STD_MODE,
        .data_width = THIRTY_TWO_BIT,
        .channels_num = TWO_CH,
        .timing = NONE_TIMING_MODE,
        .clk_edge = RISING_EDGE,
        .div_number = INMP441_DIV_NUMBER,
        .number_of_channels = INMP441_CHANNEL_NUMBER,
    };
    errcode_t ret;

    // 确保 GPIO_00 设置为正确的复用模式
    (void)uapi_pin_set_mode(INMP441_I2S_WS_PIN, INMP441_I2S_PIN_MODE);
    
    // [关键] 对于 WS 引脚，在硬件上电期间必须保持稳定
    (void)uapi_pin_set_pull(INMP441_I2S_WS_PIN, PIN_PULL_TYPE_DISABLE);
    
    (void)uapi_i2s_deinit(INMP441_I2S_BUS);
    ret = uapi_i2s_init(INMP441_I2S_BUS, INMP441_OnData);
    if (ret != ERRCODE_SUCC) {
        g_inmp441_ready = 0;
        return ret;
    }

    INMP441_PinMux_Init();

    ret = uapi_i2s_set_config(INMP441_I2S_BUS, &config);
    if (ret != ERRCODE_SUCC) {
        g_inmp441_ready = 0;
        return ret;
    }

    ret = uapi_i2s_read_start(INMP441_I2S_BUS);
    g_inmp441_ready = (ret == ERRCODE_SUCC) ? 1 : 0;
    return ret;
}

errcode_t INMP441_Sensor_Read(INMP441_Data_t *out_data)
{
    if (out_data == NULL) {
        return ERRCODE_INVALID_PARAM;
    }
    if (!g_inmp441_ready) {
        return ERRCODE_FAIL;
    }

    out_data->level = g_inmp441_level;
    return ERRCODE_SUCC;
}

errcode_t INMP441_Sensor_CopyLatestAudio(int16_t *out_audio, uint32_t max_samples, uint32_t *out_valid_samples)
{
    uint32_t available_samples;
    uint32_t write_index;
    uint32_t copy_samples;
    uint32_t start_index;

    if ((out_audio == NULL) || (out_valid_samples == NULL) || (max_samples == 0)) {
        return ERRCODE_INVALID_PARAM;
    }
    if (!g_inmp441_ready) {
        return ERRCODE_FAIL;
    }

    write_index = g_inmp441_audio_write_index;
    available_samples = g_inmp441_audio_total_samples;
    if (available_samples > INMP441_AUDIO_WINDOW_SAMPLES) {
        available_samples = INMP441_AUDIO_WINDOW_SAMPLES;
    }

    copy_samples = (available_samples < max_samples) ? available_samples : max_samples;
    start_index = (write_index + INMP441_AUDIO_WINDOW_SAMPLES - copy_samples) % INMP441_AUDIO_WINDOW_SAMPLES;

    (void)memset(out_audio, 0, sizeof(int16_t) * max_samples);
    for (uint32_t i = 0; i < copy_samples; i++) {
        out_audio[i] = g_inmp441_audio_ring[(start_index + i) % INMP441_AUDIO_WINDOW_SAMPLES];
    }

    *out_valid_samples = copy_samples;
    return ERRCODE_SUCC;
}
