# JS 采集端说明

## 1. 角色定位

`application/JS` 是 WS63 传感器采集端固件。

它负责：

- 采集 `MPU6050` 振动数据。
- 采集 `INMP441` 音频数据。
- 采集 `NTC` 温度数据。
- 聚合成固定长度模型窗口。
- 通过 `SLE` 以二进制分包方式发送给主设备桥接端。

当前不是旧版单点 JSON 上报逻辑，而是面向多模态模型的固定窗口上报逻辑。

## 2. 目录结构

```text
application/JS/
|-- main.c
|-- sle_module.c
|-- sle_module.h
|-- sensor_module.c
|-- sensor_module.h
|-- mpu6050_sensor.c
|-- mpu6050_sensor.h
|-- inmp441_sensor.c
|-- inmp441_sensor.h
|-- temperature_sensor.c
|-- temperature_sensor.h
|-- sensor_node_config.h
|-- CMakeLists.txt
|-- Kconfig
`-- README.md
```

## 3. 分层设计

### 3.1 `main.c`

职责：

- 初始化传感器和 SLE 服务端。
- 接收主设备 `START/STOP/STATUS` 控制命令。
- 调用 `Sensor_CaptureModelFrame()` 采集一帧模型数据。
- 按协议发送 `META/AUDIO/VIBRATION/TEMPERATURE/END` 五类分包。

### 3.2 `sensor_module.c/.h`

职责：

- 作为中间层统一初始化底层传感器模块。
- 将底层数据整理成适配模型的固定窗口。
- 对上层屏蔽硬件细节。

核心接口：

```c
void Sensor_Init(void);
errcode_t Sensor_CaptureModelFrame(void);
void Sensor_GetModelFrameInfo(SensorModelFrameInfo_t *out_info);
const int16_t *Sensor_GetModelAudioWindow(void);
const int16_t *Sensor_GetModelVibrationWindow(void);
const int16_t *Sensor_GetModelTemperatureWindow(void);
```

### 3.3 底层传感器模块

#### `mpu6050_sensor.c/.h`

- 负责 `MPU6050` 的 I2C 初始化和读取。
- 当前上报给模型的是三轴加速度窗口。
- 陀螺仪值保存在帧元信息里，便于调试和扩展。

#### `inmp441_sensor.c/.h`

- 负责 `INMP441` 的 I2S 初始化。
- 在回调中维护最近 `32000` 点单声道 PCM 环形缓冲。
- 可向中间层导出最近 2 秒音频窗口。

#### `temperature_sensor.c/.h`

- 当前实现为 `NTC + ADC` 温度采样。
- 连续采样 8 次做均值。
- 用 Beta 模型换算摄氏度。

## 4. 模型窗口规格

当前采集端按模型要求输出：

- 音频：`32000` 点 `int16 PCM`，目标对应 `2s @ 16kHz`
- 振动：`[3][2000]` 连续 `int16`
- 温度：`60` 点 `int16`，单位 `0.1C`

同时每帧元信息中包含：

- `source_id`
- `device_id`

用于 Atlas 和 backend 做多设备标识。

对应宏定义：

```c
#define SENSOR_MODEL_AUDIO_SAMPLES          32000U
#define SENSOR_MODEL_VIB_CHANNELS           3U
#define SENSOR_MODEL_VIB_SAMPLES            2000U
#define SENSOR_MODEL_TEMP_SAMPLES           60U
```

## 5. SLE 二进制分包协议

每个分包都有固定包头：

```c
typedef struct __attribute__((packed)) {
    uint16_t magic;
    uint8_t version;
    uint8_t type;
    uint16_t frame_id;
    uint16_t chunk_index;
    uint16_t chunk_total;
    uint16_t payload_len;
} ModelPacketHeader_t;
```

字段说明：

- `magic = 0x4A53`
- `version = 1`
- `type`
  - `1`: META
  - `2`: AUDIO
  - `3`: VIBRATION
  - `4`: TEMPERATURE
  - `5`: END

发送顺序：

1. `META`
2. `AUDIO`
3. `VIBRATION`
4. `TEMPERATURE`
5. `END`

## 6. 传感器硬件默认配置

### 6.0 传感器引脚汇总

| 传感器 | 信号 | 当前代码引脚 | 说明 |
| :--- | :--- | :--- | :--- |
| MPU6050 | SDA | `GPIO_15` | 物理 `PIN26(UART1_TX)`，复用为 `I2C1_SDA` |
| MPU6050 | SCL | `GPIO_16` | 物理 `PIN27(UART1_RX)`，复用为 `I2C1_SCL` |
| INMP441 | SCK/BCLK | `GPIO_10` | 物理 `PIN14`，复用为 `I2S_SCLK` |
| INMP441 | WS/LRCLK | `GPIO_00` | 物理 `PIN4`，复用为 `I2S_WS` |
| INMP441 | SD | `GPIO_12` | 物理 `PIN16`，复用为 `I2S_DI`，麦克风数据输入到 WS63 |
| NTC(4引脚) | AO | `ADC_CHANNEL_0` | 对应 `IO_7 / GPIO_7 / ADC_INPUT0` |
| NTC(4引脚) | DO | `GPIO_08` | 数字阈值输出输入脚 |
| NTC(4引脚) | VCC | `3.3V` | 模块供电 |
| NTC(4引脚) | GND | `GND` | 模块地 |

说明：

- 根据 `WS63V100` 硬件用户指南，ADC 仅可复用到 `GPIO_07~GPIO_12`。
- 当前 `INMP441` 实际只保留 `SCK/WS/SD` 三根必要线，不再额外配置未使用的 `I2S_DO(GPIO_09)`。
- `4引脚 NTC` 推荐使用 `AO(GPIO_07/ADC0) + DO(GPIO_08)` 组合，既满足模块形态，也尽量避开额外占用敏感复用脚。

### 6.1 MPU6050

- 总线：`I2C_BUS_1`
- 波特率：`400000`
- SDA：`GPIO_15`，对应物理 `PIN26(UART1_TX)`
- SCL：`GPIO_16`，对应物理 `PIN27(UART1_RX)`
- Pin Mode：`PIN_MODE_2`
- 地址：优先 `0x68`，失败后尝试 `0x69`

### 6.2 INMP441

- 总线：`SIO_BUS_0`
- 模式：`I2S Master`
- 数据宽度：`32 bit`
- 通道数：`2`
- I2S 引脚复用：当前在应用层仅配置必要接收脚
- 当前默认 I2S 管脚：
  - `GPIO_10 -> I2S_SCLK`
  - `GPIO_00 -> I2S_WS`
  - `GPIO_12 -> I2S_DI`

说明：

- 当前项目将 `WS/LRCLK` 放到 `GPIO_00`，以匹配你的目标接线方案并避开原来 `GPIO_11` 的启动配置风险。
- 当前项目继续避免额外占用未使用的 `I2S_DO` 相关脚。

### 6.3 NTC 温度传感器

当前默认参数位于 `temperature_sensor.c`：

- 模块形态：`AO / DO / VCC / GND` 四引脚
- AO：`ADC_CHANNEL_0`
- AO 输入脚：`IO_7 / GPIO_7 / ADC_INPUT0`
- DO 输入脚：`GPIO_08`
- ADC 参考电压：`3600mV`
- 上拉电阻：`10K`
- NTC 标称阻值：`10K`
- Beta：`3950`
- 分压结构：`VREF -> 上拉电阻 -> AO采样点 -> NTC -> GND`

说明：

- 当前模型仍主要使用 `AO` 的模拟温度值。
- `DO` 已在代码中初始化为数字输入，便于后续扩展阈值触发或安全保护逻辑。

如果你的 NTC 参数不同，只需要修改 `temperature_sensor.c` 顶部宏定义。

## 7. 控制命令

桥接端可向采集端发送：

- `START`：开始发送模型数据包
- `STOP`：暂停发送模型数据包
- `STATUS`：查询当前状态

## 8. 构建方式

推荐使用角色构建脚本：

```bash
bash src/build_js_role.sh sensor
```

脚本会切换 `CONFIG_ENABLE_JS_APP=y`、关闭 `CONFIG_ENABLE_JS_MASTER_APP`，并清理应用 CMake 缓存，避免和桥接端角色互相串库。

产物会复制到：

```text
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-sensor.bin
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-sensor-sign.bin
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-sensor.hex
```

## 9. 当前限制

- `MPU6050` 目前主要向模型提供加速度窗口，尚未做零偏校准和滤波。
- `INMP441` 采样率目标按模型按 `16kHz` 组织，但实际板级时钟仍需结合硬件确认。
- 采集端只负责发原始窗口，不负责模型前处理。
- 模型前处理、推理和结果输出都在 Atlas 侧完成。
- 默认 `g_reporting_enabled = true`，但只有 SLE 已连接时才会采集并发送模型帧。
- 桥接端连接成功后会下发一次 `START`，也支持后续 `STOP/STATUS` 控制。

## 10. 多设备部署说明

如果要部署多个采集端，请先修改 `sensor_node_config.h`：

```c
#define JS_SENSOR_SOURCE_ID   1U
#define JS_SENSOR_DEVICE_ID   1U
#define JS_SENSOR_DEVICE_NAME "WS63_JS_Node_01"
```

要求：

- 每个采集端使用唯一的 `source_id`
- 每个采集端建议使用唯一的 `device_name`
