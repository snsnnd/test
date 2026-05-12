#include "sensor_module.h"
#include <string.h>
#include <stdio.h>
#include "systick.h"
#include "sensor_node_config.h"
#include "mpu6050_sensor.h"
#include "inmp441_sensor.h"
#include "temperature_sensor.h"

static int16_t g_model_audio_window[SENSOR_MODEL_AUDIO_SAMPLES] = { 0 };
static int16_t g_model_vibration_window[SENSOR_MODEL_VIB_CHANNELS][SENSOR_MODEL_VIB_SAMPLES] = { 0 };
static int16_t g_model_temperature_window[SENSOR_MODEL_TEMP_SAMPLES] = { 0 };
static SensorModelFrameInfo_t g_model_frame_info = { 0 };

static int16_t Sensor_Temperature_To_DeciCelsius(float value)
{
    return (int16_t)(value * 10.0f);
}

void Sensor_Init(void) {
    errcode_t ret;

    printf("[Sensor] 初始化传感器模块...\r\n");
    uapi_systick_init();

    ret = MPU6050_Sensor_Init();
    if (ret == ERRCODE_SUCC) {
        printf("[Sensor] MPU6050 初始化成功\r\n");
    } else {
        printf("[Sensor] MPU6050 初始化失败, ret=0x%08lx\r\n", (unsigned long)ret);
    }

    ret = INMP441_Sensor_Init();
    if (ret == ERRCODE_SUCC) {
        printf("[Sensor] INMP441 初始化成功\r\n");
    } else {
        printf("[Sensor] INMP441 初始化失败, ret=0x%08lx\r\n", (unsigned long)ret);
    }

    ret = Temperature_Sensor_Init();
    if (ret == ERRCODE_SUCC) {
        printf("[Sensor] NTC 温度传感器初始化成功\r\n");
    } else {
        printf("[Sensor] NTC 温度传感器初始化失败, ret=0x%08lx\r\n", (unsigned long)ret);
    }
}

void Sensor_ReadData(SensorData_t *out_data) {
    MPU6050_Data_t imu_data = { 0 };
    INMP441_Data_t mic_data = { 0 };
    TemperatureSensor_Data_t temperature_data = { 0 };

    if (out_data == NULL) {
        return;
    }

    (void)memset(out_data, 0, sizeof(*out_data));

    out_data->imu_ready = MPU6050_Sensor_IsReady();
    out_data->mic_ready = INMP441_Sensor_IsReady();
    out_data->temperature_ready = Temperature_Sensor_IsReady();
    out_data->temperature = 0.0f;

    if (out_data->imu_ready && (MPU6050_Sensor_Read(&imu_data) == ERRCODE_SUCC)) {
        out_data->vib_x = imu_data.accel_x;
        out_data->vib_y = imu_data.accel_y;
        out_data->vib_z = imu_data.accel_z;
        out_data->gyro_x = imu_data.gyro_x;
        out_data->gyro_y = imu_data.gyro_y;
        out_data->gyro_z = imu_data.gyro_z;
    } else {
        out_data->imu_ready = 0;
    }

    if (out_data->mic_ready && (INMP441_Sensor_Read(&mic_data) == ERRCODE_SUCC)) {
        out_data->mic_level = mic_data.level;
    } else {
        out_data->mic_ready = 0;
    }

    if (Temperature_Sensor_Read(&temperature_data) == ERRCODE_SUCC) {
        out_data->temperature = temperature_data.value;
    }
}

errcode_t Sensor_CaptureModelFrame(void)
{
    MPU6050_Data_t imu_data = { 0 };
    TemperatureSensor_Data_t temperature_data = { 0 };
    uint32_t temperature_index = 0;
    errcode_t audio_ret;

    (void)memset(g_model_audio_window, 0, sizeof(g_model_audio_window));
    (void)memset(g_model_vibration_window, 0, sizeof(g_model_vibration_window));
    (void)memset(g_model_temperature_window, 0, sizeof(g_model_temperature_window));
    (void)memset(&g_model_frame_info, 0, sizeof(g_model_frame_info));

    g_model_frame_info.source_id = JS_SENSOR_SOURCE_ID;
    g_model_frame_info.device_id = JS_SENSOR_DEVICE_ID;
    g_model_frame_info.capture_timestamp_us = (uint32_t)uapi_systick_get_us();
    g_model_frame_info.audio_target_rate_hz = SENSOR_MODEL_AUDIO_TARGET_RATE_HZ;
    g_model_frame_info.vib_sample_interval_us = SENSOR_MODEL_VIB_SAMPLE_INTERVAL_US;
    g_model_frame_info.imu_ready = MPU6050_Sensor_IsReady();
    g_model_frame_info.mic_ready = INMP441_Sensor_IsReady();
    g_model_frame_info.temperature_ready = Temperature_Sensor_IsReady();

    for (uint32_t i = 0; i < SENSOR_MODEL_VIB_SAMPLES; i++) {
        if (g_model_frame_info.imu_ready && (MPU6050_Sensor_Read(&imu_data) == ERRCODE_SUCC)) {
            g_model_vibration_window[0][i] = imu_data.accel_x;
            g_model_vibration_window[1][i] = imu_data.accel_y;
            g_model_vibration_window[2][i] = imu_data.accel_z;
            g_model_frame_info.vib_valid_samples = (uint16_t)(i + 1);
            g_model_frame_info.last_accel_x = imu_data.accel_x;
            g_model_frame_info.last_accel_y = imu_data.accel_y;
            g_model_frame_info.last_accel_z = imu_data.accel_z;
            g_model_frame_info.last_gyro_x = imu_data.gyro_x;
            g_model_frame_info.last_gyro_y = imu_data.gyro_y;
            g_model_frame_info.last_gyro_z = imu_data.gyro_z;
        } else {
            g_model_frame_info.imu_ready = 0;
        }

        while ((temperature_index < SENSOR_MODEL_TEMP_SAMPLES) &&
            ((((uint64_t)(i + 1) * SENSOR_MODEL_TEMP_SAMPLES) / SENSOR_MODEL_VIB_SAMPLES) > temperature_index)) {
            if (g_model_frame_info.temperature_ready && (Temperature_Sensor_Read(&temperature_data) == ERRCODE_SUCC)) {
                g_model_temperature_window[temperature_index] = Sensor_Temperature_To_DeciCelsius(temperature_data.value);
                g_model_frame_info.temp_valid_samples = (uint16_t)(temperature_index + 1);
            } else {
                g_model_frame_info.temperature_ready = 0;
                if (temperature_index > 0) {
                    g_model_temperature_window[temperature_index] = g_model_temperature_window[temperature_index - 1];
                }
            }
            temperature_index++;
        }

        if ((i + 1) < SENSOR_MODEL_VIB_SAMPLES) {
            (void)uapi_systick_delay_us(SENSOR_MODEL_VIB_SAMPLE_INTERVAL_US);
        }
    }

    while (temperature_index < SENSOR_MODEL_TEMP_SAMPLES) {
        if (temperature_index > 0) {
            g_model_temperature_window[temperature_index] = g_model_temperature_window[temperature_index - 1];
        }
        temperature_index++;
    }

    audio_ret = INMP441_Sensor_CopyLatestAudio(g_model_audio_window,
        SENSOR_MODEL_AUDIO_SAMPLES,
        &g_model_frame_info.audio_valid_samples);
    if (audio_ret != ERRCODE_SUCC) {
        g_model_frame_info.mic_ready = 0;
        g_model_frame_info.audio_valid_samples = 0;
    }

    if ((g_model_frame_info.vib_valid_samples == 0) &&
        (g_model_frame_info.audio_valid_samples == 0) &&
        (g_model_frame_info.temp_valid_samples == 0)) {
        return ERRCODE_FAIL;
    }

    return ERRCODE_SUCC;
}

void Sensor_GetModelFrameInfo(SensorModelFrameInfo_t *out_info)
{
    if (out_info == NULL) {
        return;
    }

    *out_info = g_model_frame_info;
}

const int16_t *Sensor_GetModelAudioWindow(void)
{
    return g_model_audio_window;
}

const int16_t *Sensor_GetModelVibrationWindow(void)
{
    return &g_model_vibration_window[0][0];
}

const int16_t *Sensor_GetModelTemperatureWindow(void)
{
    return g_model_temperature_window;
}
