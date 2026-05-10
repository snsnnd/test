#include <stdbool.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "cmsis_os2.h"
#include "app_init.h"

// 引入我们自己写的模块
#include "sensor_node_config.h"
#include "sensor_module.h"
#include "sle_module.h"

// 定义星闪设备名称
#define MY_SLE_DEV_NAME JS_SENSOR_DEVICE_NAME
#define MODEL_PACKET_MAGIC 0x4A53
#define MODEL_PACKET_VERSION 1
#define MODEL_PAYLOAD_MAX_BYTES 128
#define MODEL_SEND_RETRY_COUNT 3

static volatile bool g_reporting_enabled = true;
static uint16_t g_model_frame_id = 0;

typedef enum {
    MODEL_PACKET_TYPE_META = 1,
    MODEL_PACKET_TYPE_AUDIO = 2,
    MODEL_PACKET_TYPE_VIBRATION = 3,
    MODEL_PACKET_TYPE_TEMPERATURE = 4,
    MODEL_PACKET_TYPE_END = 5,
} ModelPacketType_t;

typedef struct __attribute__((packed)) {
    uint16_t magic;
    uint8_t version;
    uint8_t type;
    uint16_t frame_id;
    uint16_t chunk_index;
    uint16_t chunk_total;
    uint16_t payload_len;
} ModelPacketHeader_t;

typedef struct __attribute__((packed)) {
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
    uint8_t audio_format;
    uint8_t vibration_layout;
    uint8_t temperature_format;
    uint8_t reserved;
    int16_t last_accel_x;
    int16_t last_accel_y;
    int16_t last_accel_z;
    int16_t last_gyro_x;
    int16_t last_gyro_y;
    int16_t last_gyro_z;
} ModelFrameMeta_t;

static bool Command_Equals(const uint8_t *data, uint16_t len, const char *command)
{
    size_t command_len;

    if (data == NULL || command == NULL) {
        return false;
    }

    command_len = strlen(command);
    return ((size_t)len == command_len) && (memcmp(data, command, command_len) == 0);
}

static int JS_SendPacket(ModelPacketType_t type,
    uint16_t frame_id,
    uint16_t chunk_index,
    uint16_t chunk_total,
    const uint8_t *payload,
    uint16_t payload_len)
{
    uint8_t packet[sizeof(ModelPacketHeader_t) + MODEL_PAYLOAD_MAX_BYTES] = { 0 };
    ModelPacketHeader_t header = {
        .magic = MODEL_PACKET_MAGIC,
        .version = MODEL_PACKET_VERSION,
        .type = (uint8_t)type,
        .frame_id = frame_id,
        .chunk_index = chunk_index,
        .chunk_total = chunk_total,
        .payload_len = payload_len,
    };

    (void)memcpy(packet, &header, sizeof(header));
    if ((payload != NULL) && (payload_len > 0)) {
        (void)memcpy(&packet[sizeof(header)], payload, payload_len);
    }

    for (uint32_t retry = 0; retry < MODEL_SEND_RETRY_COUNT; retry++) {
        if (SLE_Send_Data(packet, (uint16_t)(sizeof(header) + payload_len)) == 0) {
            return 0;
        }
        osDelay(1);
    }

    return -1;
}

static int JS_SendChunkedBuffer(ModelPacketType_t type, uint16_t frame_id, const uint8_t *buffer, uint32_t total_len)
{
    uint16_t chunk_total;

    if ((buffer == NULL) || (total_len == 0)) {
        return -1;
    }

    chunk_total = (uint16_t)((total_len + MODEL_PAYLOAD_MAX_BYTES - 1) / MODEL_PAYLOAD_MAX_BYTES);
    for (uint16_t chunk_index = 0; chunk_index < chunk_total; chunk_index++) {
        uint32_t offset = (uint32_t)chunk_index * MODEL_PAYLOAD_MAX_BYTES;
        uint32_t remaining = total_len - offset;
        uint16_t chunk_len = (remaining > MODEL_PAYLOAD_MAX_BYTES) ? MODEL_PAYLOAD_MAX_BYTES : (uint16_t)remaining;

        if (JS_SendPacket(type, frame_id, chunk_index, chunk_total, &buffer[offset], chunk_len) != 0) {
            return -1;
        }
    }

    return 0;
}

static int JS_SendModelFrame(uint16_t frame_id)
{
    SensorModelFrameInfo_t frame_info = { 0 };
    ModelFrameMeta_t meta = { 0 };

    Sensor_GetModelFrameInfo(&frame_info);

    meta.source_id = frame_info.source_id;
    meta.device_id = frame_info.device_id;
    meta.capture_timestamp_us = frame_info.capture_timestamp_us;
    meta.audio_target_rate_hz = frame_info.audio_target_rate_hz;
    meta.audio_valid_samples = frame_info.audio_valid_samples;
    meta.vib_valid_samples = frame_info.vib_valid_samples;
    meta.temp_valid_samples = frame_info.temp_valid_samples;
    meta.vib_sample_interval_us = frame_info.vib_sample_interval_us;
    meta.imu_ready = frame_info.imu_ready;
    meta.mic_ready = frame_info.mic_ready;
    meta.temperature_ready = frame_info.temperature_ready;
    meta.audio_format = 1;      // PCM16 mono, little-endian
    meta.vibration_layout = 1;  // channel-major [3][2000]
    meta.temperature_format = 1; // int16, 0.1C
    meta.last_accel_x = frame_info.last_accel_x;
    meta.last_accel_y = frame_info.last_accel_y;
    meta.last_accel_z = frame_info.last_accel_z;
    meta.last_gyro_x = frame_info.last_gyro_x;
    meta.last_gyro_y = frame_info.last_gyro_y;
    meta.last_gyro_z = frame_info.last_gyro_z;

    if (JS_SendPacket(MODEL_PACKET_TYPE_META, frame_id, 0, 1, (const uint8_t *)&meta, sizeof(meta)) != 0) {
        return -1;
    }

    if (JS_SendChunkedBuffer(MODEL_PACKET_TYPE_AUDIO,
        frame_id,
        (const uint8_t *)Sensor_GetModelAudioWindow(),
        SENSOR_MODEL_AUDIO_SAMPLES * sizeof(int16_t)) != 0) {
        return -1;
    }

    if (JS_SendChunkedBuffer(MODEL_PACKET_TYPE_VIBRATION,
        frame_id,
        (const uint8_t *)Sensor_GetModelVibrationWindow(),
        SENSOR_MODEL_VIB_CHANNELS * SENSOR_MODEL_VIB_SAMPLES * sizeof(int16_t)) != 0) {
        return -1;
    }

    if (JS_SendChunkedBuffer(MODEL_PACKET_TYPE_TEMPERATURE,
        frame_id,
        (const uint8_t *)Sensor_GetModelTemperatureWindow(),
        SENSOR_MODEL_TEMP_SAMPLES * sizeof(int16_t)) != 0) {
        return -1;
    }

    return JS_SendPacket(MODEL_PACKET_TYPE_END, frame_id, 0, 1, NULL, 0);
}

// 当收到主设备（DAYU200）发来的指令时，触发此函数
static void On_SLE_Data_Received(uint8_t *data, uint16_t len) {
    printf("[Main] 收到主设备指令! 长度:%u, 内容:%.*s\r\n", len, (int)len, (const char *)data);

    if (Command_Equals(data, len, "STOP")) {
        g_reporting_enabled = false;
        printf("[Main] 已暂停传感器数据上报\r\n");
        return;
    }

    if (Command_Equals(data, len, "START")) {
        g_reporting_enabled = true;
        printf("[Main] 已恢复传感器数据上报\r\n");
        return;
    }

    if (Command_Equals(data, len, "STATUS")) {
        printf("[Main] 当前上报状态: %s\r\n", g_reporting_enabled ? "RUNNING" : "STOPPED");
    }
}

// 主业务线程
static void JS_MainTask(void *arg) {
    (void)arg;
    
    printf("\r\n=======================================\r\n");
    printf("[JS App] 工业异常检测终端启动...\r\n");
    printf("=======================================\r\n");

    // 1. 初始化传感器
    Sensor_Init();

    // 2. 初始化星闪并注册回调
    SLE_Server_Init();
    SLE_Register_Receive_Callback(On_SLE_Data_Received);

    // 3. 开始广播，等待主设备连接
    SLE_Start_Advertising(MY_SLE_DEV_NAME);

    // 4. 进入核心工作循环
    while (1) {
        if (!g_reporting_enabled) {
            osDelay(10);
            continue;
        }

        if (!SLE_IsConnected()) {
            osDelay(10);
            continue;
        }

        if (Sensor_CaptureModelFrame() != ERRCODE_SUCC) {
            osDelay(10);
            continue;
        }

        if (JS_SendModelFrame(g_model_frame_id) == 0) {
            printf("[JS App] 模型帧发送完成 frame_id=%u\r\n", g_model_frame_id);
            g_model_frame_id++;
        } else {
            printf("[JS App] 模型帧发送失败 frame_id=%u\r\n", g_model_frame_id);
        }

        osDelay(10);
    }
}

// 线程注册
static void JS_App_Entry(void) {
    osThreadAttr_t attr = {0};
    attr.name = "JS_MainTask";
    attr.stack_size = 1024 * 8; // SLE 通信可能需要大一点的栈空间，给 8KB
    attr.priority = osPriorityNormal;

    if (osThreadNew(JS_MainTask, NULL, &attr) == NULL) {
        printf("[JS App] 线程创建失败!\r\n");
    }
}

app_run(JS_App_Entry);
