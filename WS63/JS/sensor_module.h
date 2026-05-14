#ifndef SENSOR_MODULE_H
#define SENSOR_MODULE_H

#include <stdint.h>
#include "errcode.h"

#define SENSOR_MODEL_AUDIO_SAMPLES            32000U
#define SENSOR_MODEL_VIB_CHANNELS             3U
#define SENSOR_MODEL_VIB_SAMPLES              2000U
#define SENSOR_MODEL_TEMP_SAMPLES             60U
#define SENSOR_MODEL_VIB_SAMPLE_INTERVAL_US   1000U
#define SENSOR_MODEL_AUDIO_TARGET_RATE_HZ     16000U

// 统一打包当前传感器采样结果，作为上层业务只感知的中间层数据结构。
typedef struct {
    int16_t vib_x;
    int16_t vib_y;
    int16_t vib_z;
    int16_t gyro_x;
    int16_t gyro_y;
    int16_t gyro_z;
    uint32_t mic_level;
    float temperature;
    uint8_t imu_ready;
    uint8_t mic_ready;
    uint8_t temperature_ready;
} SensorData_t;

typedef struct {
    uint16_t source_id;
    uint16_t device_id;
    uint32_t capture_timestamp_us;
    uint32_t audio_target_rate_hz;
    uint32_t audio_valid_samples;
    uint16_t vib_valid_samples;
    uint16_t temp_valid_samples;
    uint16_t vib_sample_interval_us;
    uint8_t imu_ready;
    uint8_t mic_ready;
    uint8_t temperature_ready;
    int16_t last_accel_x;
    int16_t last_accel_y;
    int16_t last_accel_z;
    int16_t last_gyro_x;
    int16_t last_gyro_y;
    int16_t last_gyro_z;
} SensorModelFrameInfo_t;

// 中间层初始化底层传感器模块。
void Sensor_Init(void);

// 从各底层传感器模块聚合最新数据。
void Sensor_ReadData(SensorData_t *out_data);

// 采集一帧适配多模态模型的固定窗口数据。
errcode_t Sensor_CaptureModelFrame(void);

// 获取最近一帧模型数据的元信息。
void Sensor_GetModelFrameInfo(SensorModelFrameInfo_t *out_info);

// 获取最近一帧音频窗口，数据格式为 int16 单声道 PCM。
const int16_t *Sensor_GetModelAudioWindow(void);

// 获取最近一帧振动窗口，内存布局为 [3][2000] 的连续 int16 数据。
const int16_t *Sensor_GetModelVibrationWindow(void);

// 获取最近一帧温度窗口，数据格式为 0.1 摄氏度定点值。
const int16_t *Sensor_GetModelTemperatureWindow(void);

#endif // SENSOR_MODULE_H
