# JS_MASTER 桥接端说明

## 1. 角色定位

`application/JS_MASTER` 是 WS63 主设备桥接端固件。

它负责：

- 作为 `SLE Client` 连接传感器采集端 `WS63_JS_Node_01`
- 主动扫描附近符合条件的 `JS` 采集端广播
- 将扫描到的节点列表周期性通过 UART 上报给 Atlas
- 接收 Atlas 通过 UART 下发的目标选择命令
- 接收采集端发来的二进制模型分包
- 通过 UART 串口将原始模型分包原样转发到 Atlas 200I

它不做模型前处理，也不做推理，只做桥接。

## 2. 数据流

```text
WS63(JS) --SLE--> WS63(JS_MASTER) --UART--> Atlas 200I
```

说明：

- 当前 `JS_MASTER -> Atlas` 不再走 `WiFi/TCP`。
- 当前实现是 `UART` 串口连接。

## 3. 主要文件

```text
application/JS_MASTER/
|-- main.c
|-- sle_client_module.c
|-- sle_client_module.h
|-- atlas_bridge.c
|-- atlas_bridge.h
|-- atlas_bridge_config.h
|-- js_master_target_config.h
|-- CMakeLists.txt
`-- README.md
```

## 4. 模块职责

### 4.1 `main.c`

- 初始化桥接模块
- 初始化 SLE Client
- Atlas 选定采集端并完成连接后自动发送一次 `START`
- 将收到的每个模型分包交给桥接队列

### 4.2 `sle_client_module.c/.h`

- 负责扫描、连接、配对、发现服务和特征
- 接收来自采集端的通知分包
- 支持向采集端发送控制命令

附近设备扫描能力说明：

- `JS_MASTER` 会主动扫描附近广播
- 当前默认寻找名称为 `WS63_JS_Node_01` 的采集端
- 同时也会校验目标服务 UUID

多目标识别与单目标选择说明：

- `JS_MASTER` 会识别并缓存多个附近 `JS` 节点
- 启动后默认只扫描并上报设备列表，不自动连接
- Atlas 通过串口下发 `SELECT_TARGET` 后才连接指定节点
- 当前不会同时连接多个采集端

### 4.3 `atlas_bridge.c/.h`

- 负责初始化 UART 串口
- 负责向 Atlas 串口持续发送原始模型分包
- 使用消息队列缓存收到的模型分包
- 在独立线程中做 SLE 包到 UART 的转发
- 周期性发送附近节点发现状态
- 解析 Atlas 下发的目标切换控制帧

## 5. 需要先修改的配置

在 `atlas_bridge_config.h` 中修改以下宏：

```c
#define BRIDGE_UART_BUS          UART_BUS_2
#define BRIDGE_UART_BAUDRATE     921600
#define BRIDGE_UART_TX_PIN       GPIO_07
#define BRIDGE_UART_RX_PIN       GPIO_08
#define BRIDGE_UART_TX_PIN_MODE  PIN_MODE_2
#define BRIDGE_UART_RX_PIN_MODE  PIN_MODE_2
```

说明：

- 需要保证 WS63 MASTER 与 Atlas 200I 的 UART 物理连线正确
- Atlas 侧串口服务需要配置同样的串口波特率，例如 `921600`。
- 当前桥接端使用 `UART2(GPIO_07 TX / GPIO_08 RX)` 作为业务串口。
- `JS_MASTER` 和 Atlas 需要交叉连接 TX/RX，并共地。

`js_master_target_config.h` 是早期固定目标模式遗留配置。当前代码不再启动后自动连接该宏定义目标，实际目标由 Atlas 通过 UART 控制帧选择。

## 6. Atlas 控制帧

桥接端和 Atlas 之间复用同一个 UART：

- `JS` 模型数据包：`JS_MASTER` 原样转发，包头 `magic = 0x4A53`。
- 桥接控制帧：用于发现状态上报和目标选择，包头 `magic = 0x434D`。

控制帧头：

```c
typedef struct __attribute__((packed)) {
    uint16_t magic;
    uint8_t version;
    uint8_t type;
    uint16_t payload_len;
} bridge_ctrl_header_t;
```

类型：

- `1`: `DISCOVERY_STATUS`，桥接端每秒上报一次附近节点、当前目标和连接状态。
- `2`: `SELECT_TARGET`，Atlas 下发目标节点名称。
- `3`: `SWITCH_ACK`，桥接端确认目标选择请求。

`SELECT_TARGET` payload 为固定长度目标名称：

```c
typedef struct __attribute__((packed)) {
    char target_name[32];
} bridge_select_payload_t;
```

## 7. 构建方式

使用角色构建脚本：

```bash
bash src/build_js_role.sh bridge
```

脚本会切换 `CONFIG_ENABLE_JS_MASTER_APP=y`、关闭 `CONFIG_ENABLE_JS_APP`，并清理应用 CMake 缓存，避免和采集端角色互相串库。

产物会复制到：

```text
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-bridge.bin
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-bridge-sign.bin
src/output/ws63/acore/ws63-liteos-app/dist/ws63-js-bridge.hex
```

## 8. 运行日志预期

正常情况下会看到：

- UART 初始化成功
- 开始扫描并上报设备列表
- Atlas 下发目标后 SLE 链路就绪
- 已向采集端发送 `START`

## 9. 枢纽定位

当前系统里，`JS_MASTER + Atlas 200I` 共同构成边缘核心枢纽：

- `JS_MASTER` 负责近场 `SLE` 侧接入和原始模型包上送。
- `Atlas 200I` 负责推理、后端服务和面向 DAYU200 的网络接口。

DAYU200 前端不直接连 `JS_MASTER`，而是通过网络访问 Atlas 侧后端。

当前版本已经实现 `UART` 串口接入 Atlas。

## 10. 当前限制

- 当前桥接端默认一次只连接一个采集端。
- 只做 UART 上行转发，不做本地缓存重放。
- UART 参数当前写在 `atlas_bridge_config.h`，后续可继续升级为 NVS 配置。
- 目标选择依赖 Atlas 侧下发控制帧；如果只接串口助手而不下发 `SELECT_TARGET`，桥接端只会扫描上报，不会自动连接。
- 如果要同时接入多个 `JS` 采集端，当前仍需要多个 `JS_MASTER`，或后续扩展为多目标扫描与多连接管理。
