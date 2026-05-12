#include "atlas_bridge.h"

#include <stdio.h>
#include <string.h>

#include "atlas_bridge_config.h"
#include "cmsis_os2.h"
#include "pinctrl.h"
#include "sle_client_module.h"
#include "uart.h"
#include "debug_print.h"

#define BRIDGE_QUEUE_PACKET_MAX_LEN     160
#define BRIDGE_QUEUE_DEPTH              128
#define BRIDGE_STATUS_REPORT_INTERVAL_MS 1000
#define BRIDGE_UART_READ_CHUNK_SIZE     64
#define BRIDGE_UART_READ_TIMEOUT_MS     20
#define BRIDGE_UART_READ_IDLE_DELAY_MS  20
#define BRIDGE_UART_CONTROL_BUFFER_SIZE 512
#define BRIDGE_CTRL_MAX_PAYLOAD_LEN     ((uint16_t)(BRIDGE_UART_CONTROL_BUFFER_SIZE - sizeof(bridge_ctrl_header_t)))

#define BRIDGE_CTRL_MAGIC               0x434D
#define BRIDGE_CTRL_VERSION             1

typedef enum {
    BRIDGE_CTRL_TYPE_DISCOVERY_STATUS = 1,
    BRIDGE_CTRL_TYPE_SELECT_TARGET = 2,
    BRIDGE_CTRL_TYPE_SWITCH_ACK = 3,
} bridge_ctrl_type_t;

typedef struct __attribute__((packed)) {
    uint16_t magic;
    uint8_t version;
    uint8_t type;
    uint16_t payload_len;
} bridge_ctrl_header_t;

typedef struct __attribute__((packed)) {
    char name[SLE_CLIENT_NODE_NAME_MAX_LEN + 1];
    int8_t rssi;
    uint8_t has_service;
    uint8_t is_selected;
    uint8_t is_connected;
} bridge_discovery_node_t;

typedef struct __attribute__((packed)) {
    char active_target[SLE_CLIENT_NODE_NAME_MAX_LEN + 1];
    uint8_t target_connected;
    uint8_t node_count;
    uint16_t reserved;
    bridge_discovery_node_t nodes[SLE_CLIENT_DISCOVERED_NODE_MAX];
} bridge_discovery_payload_t;

typedef struct __attribute__((packed)) {
    char target_name[SLE_CLIENT_NODE_NAME_MAX_LEN + 1];
} bridge_select_payload_t;

typedef struct __attribute__((packed)) {
    uint8_t accepted;
    uint8_t reserved[3];
    char active_target[SLE_CLIENT_NODE_NAME_MAX_LEN + 1];
    char message[64];
} bridge_ack_payload_t;

#define BRIDGE_THREAD_STACK_SIZE        (1024 * 8)
#define BRIDGE_THREAD_PRIORITY          osPriorityNormal
#define BRIDGE_UART_RETRY_DELAY_MS      1000
#define BRIDGE_QUEUE_WAIT_MS            100

typedef struct {
    uint16_t len;
    uint8_t data[BRIDGE_QUEUE_PACKET_MAX_LEN];
} bridge_packet_t;

static volatile bool g_bridge_ready = false;
static osMessageQueueId_t g_bridge_queue = NULL;
static uint8_t g_bridge_uart_rx_buffer[BRIDGE_UART_RX_BUFFER_SIZE] = { 0 };
static osMutexId_t g_bridge_uart_mutex = NULL;

static void Atlas_Bridge_Uart_Reset(void);
static errcode_t Atlas_Bridge_Ensure_Uart_Ready(void);

static void Atlas_Bridge_Lock_Uart(void)
{
    if (g_bridge_uart_mutex != NULL) {
        (void)osMutexAcquire(g_bridge_uart_mutex, osWaitForever);
    }
}

static void Atlas_Bridge_Unlock_Uart(void)
{
    if (g_bridge_uart_mutex != NULL) {
        (void)osMutexRelease(g_bridge_uart_mutex);
    }
}

static int Atlas_Bridge_Write_Raw(const uint8_t *payload, uint16_t len)
{
    int32_t sent_len;

    if ((payload == NULL) || (len == 0)) {
        return -1;
    }

    Atlas_Bridge_Lock_Uart();
    sent_len = uapi_uart_write(BRIDGE_UART_BUS, payload, len, BRIDGE_UART_WRITE_TIMEOUT_MS);
    Atlas_Bridge_Unlock_Uart();

    if (sent_len != (int32_t)len) {
        Atlas_Bridge_Uart_Reset();
        return -1;
    }

    return 0;
}

static int32_t Atlas_Bridge_Read_Raw(uint8_t *payload, uint16_t len)
{
    int32_t read_len;

    if ((payload == NULL) || (len == 0)) {
        return -1;
    }

    Atlas_Bridge_Lock_Uart();
    read_len = uapi_uart_read(BRIDGE_UART_BUS, payload, len, BRIDGE_UART_READ_TIMEOUT_MS);
    Atlas_Bridge_Unlock_Uart();
    return read_len;
}

static int Atlas_Bridge_Send_ControlFrame(bridge_ctrl_type_t type, const uint8_t *payload, uint16_t payload_len)
{
    uint8_t frame[sizeof(bridge_ctrl_header_t) + sizeof(bridge_discovery_payload_t)] = {0};
    bridge_ctrl_header_t header = {
        .magic = BRIDGE_CTRL_MAGIC,
        .version = BRIDGE_CTRL_VERSION,
        .type = (uint8_t)type,
        .payload_len = payload_len,
    };

    if (payload_len > sizeof(frame) - sizeof(header)) {
        return -1;
    }

    (void)memcpy(frame, &header, sizeof(header));
    if ((payload != NULL) && (payload_len > 0)) {
        (void)memcpy(frame + sizeof(header), payload, payload_len);
    }
    return Atlas_Bridge_Write_Raw(frame, (uint16_t)(sizeof(header) + payload_len));
}

static void Atlas_Bridge_Send_Switch_Ack(uint8_t accepted, const char *message)
{
    bridge_ack_payload_t ack = {0};
    bool is_connected = false;

    SLE_Client_Get_Target_State(ack.active_target, sizeof(ack.active_target), &is_connected);
    ack.accepted = accepted;
    if (message != NULL) {
        size_t msg_len = strlen(message);
        if (msg_len >= sizeof(ack.message)) {
            msg_len = sizeof(ack.message) - 1;
        }
        (void)memcpy(ack.message, message, msg_len);
        ack.message[msg_len] = '\0';
    }
    (void)Atlas_Bridge_Send_ControlFrame(BRIDGE_CTRL_TYPE_SWITCH_ACK, (const uint8_t *)&ack, sizeof(ack));
}

static void Atlas_Bridge_Send_Discovery_Status(void)
{
    bridge_discovery_payload_t payload = {0};
    SLE_ClientDiscoveredNode_t nodes[SLE_CLIENT_DISCOVERED_NODE_MAX] = {0};
    bool is_connected = false;

    SLE_Client_Get_Target_State(payload.active_target, sizeof(payload.active_target), &is_connected);
    payload.target_connected = is_connected ? 1 : 0;
    payload.node_count = SLE_Client_Get_Discovered_Nodes(nodes, SLE_CLIENT_DISCOVERED_NODE_MAX);
    for (uint8_t index = 0; index < payload.node_count; index++) {
        (void)memcpy(payload.nodes[index].name, nodes[index].name, sizeof(payload.nodes[index].name));
        payload.nodes[index].rssi = nodes[index].rssi;
        payload.nodes[index].has_service = nodes[index].has_service ? 1 : 0;
        payload.nodes[index].is_selected = nodes[index].is_selected ? 1 : 0;
        payload.nodes[index].is_connected = nodes[index].is_connected ? 1 : 0;
    }

    (void)Atlas_Bridge_Send_ControlFrame(BRIDGE_CTRL_TYPE_DISCOVERY_STATUS,
        (const uint8_t *)&payload,
        sizeof(payload));
}

static void Atlas_Bridge_Handle_Select_Target(const uint8_t *payload, uint16_t payload_len)
{
    bridge_select_payload_t select_payload = {0};

    if (payload_len != sizeof(select_payload)) {
        Atlas_Bridge_Send_Switch_Ack(0, "invalid select payload");
        return;
    }

    (void)memcpy(&select_payload, payload, sizeof(select_payload));
    select_payload.target_name[sizeof(select_payload.target_name) - 1] = '\0';
    if (select_payload.target_name[0] == '\0') {
        Atlas_Bridge_Send_Switch_Ack(0, "empty target name");
        return;
    }

    printf("[Atlas Bridge] SELECT_TARGET received target=%s payload_len=%u\r\n",
        select_payload.target_name,
        payload_len);

    SLE_Client_Select_Target(select_payload.target_name);
    Atlas_Bridge_Send_Switch_Ack(1, "target switch accepted");
}

static void Atlas_Bridge_Parse_Control_Stream(uint8_t *buffer,
    uint16_t *buffer_len,
    const uint8_t *input,
    uint16_t input_len)
{
    uint16_t write_len;

    if ((buffer == NULL) || (buffer_len == NULL) || (input == NULL) || (input_len == 0)) {
        return;
    }

    if (*buffer_len >= BRIDGE_UART_CONTROL_BUFFER_SIZE) {
        *buffer_len = 0;
    }

    write_len = (*buffer_len + input_len > BRIDGE_UART_CONTROL_BUFFER_SIZE) ?
        (uint16_t)(BRIDGE_UART_CONTROL_BUFFER_SIZE - *buffer_len) : input_len;

    if (write_len == 0) {
        *buffer_len = 0;
        return;
    }

    (void)memcpy(buffer + *buffer_len, input, write_len);
    *buffer_len = (uint16_t)(*buffer_len + write_len);

    while (*buffer_len >= sizeof(bridge_ctrl_header_t)) {
        bridge_ctrl_header_t header;
        uint16_t frame_len;

        (void)memcpy(&header, buffer, sizeof(header));

        if (header.magic != BRIDGE_CTRL_MAGIC) {
            if (*buffer_len > 1) {
                (void)memmove(buffer, buffer + 1, *buffer_len - 1);
                *buffer_len = (uint16_t)(*buffer_len - 1);
            } else {
                *buffer_len = 0;
            }
            continue;
        }

        if (header.version != BRIDGE_CTRL_VERSION) {
            if (*buffer_len > 1) {
                (void)memmove(buffer, buffer + 1, *buffer_len - 1);
                *buffer_len = (uint16_t)(*buffer_len - 1);
            } else {
                *buffer_len = 0;
            }
            continue;
        }

        if (header.payload_len > BRIDGE_CTRL_MAX_PAYLOAD_LEN) {
            if (*buffer_len > 1) {
                (void)memmove(buffer, buffer + 1, *buffer_len - 1);
                *buffer_len = (uint16_t)(*buffer_len - 1);
            } else {
                *buffer_len = 0;
            }
            continue;
        }

        frame_len = (uint16_t)(sizeof(header) + header.payload_len);

        if (*buffer_len < frame_len) {
            break;
        }

        if (header.type == BRIDGE_CTRL_TYPE_SELECT_TARGET) {
            Atlas_Bridge_Handle_Select_Target(buffer + sizeof(header), header.payload_len);
        }

        if (*buffer_len > frame_len) {
            (void)memmove(buffer, buffer + frame_len, *buffer_len - frame_len);
            *buffer_len = (uint16_t)(*buffer_len - frame_len);
        } else {
            *buffer_len = 0;
        }
    }
}

static errcode_t Atlas_Bridge_Uart_Init(void)
{
    //uapi_debug_set_out_interface(DEBUG_OUT_NONE);

    uart_attr_t uart_attr = {
        .baud_rate = BRIDGE_UART_BAUDRATE,
        .data_bits = UART_DATA_BIT_8,
        .stop_bits = UART_STOP_BIT_1,
        .parity = UART_PARITY_NONE,
    };
    uart_pin_config_t uart_pin_config = {
        .tx_pin = BRIDGE_UART_TX_PIN,
        .rx_pin = BRIDGE_UART_RX_PIN,
        .cts_pin = PIN_NONE,
        .rts_pin = PIN_NONE,
    };
    uart_buffer_config_t uart_buffer_config = {
        .rx_buffer = g_bridge_uart_rx_buffer,
        .rx_buffer_size = BRIDGE_UART_RX_BUFFER_SIZE,
    };
    errcode_t ret;

    uapi_pin_init();

#if defined(CONFIG_PINCTRL_SUPPORT_IE)
    (void)uapi_pin_set_ie(BRIDGE_UART_RX_PIN, PIN_IE_1);
#endif
    (void)uapi_pin_set_mode(BRIDGE_UART_TX_PIN, BRIDGE_UART_TX_PIN_MODE);
    (void)uapi_pin_set_mode(BRIDGE_UART_RX_PIN, BRIDGE_UART_RX_PIN_MODE);

    (void)uapi_uart_deinit(BRIDGE_UART_BUS);
    ret = uapi_uart_init(BRIDGE_UART_BUS, &uart_pin_config, &uart_attr, NULL, &uart_buffer_config);
    if (ret == ERRCODE_SUCC) {
        g_bridge_ready = true;
        printf("[Atlas Bridge] UART 已连接 Atlas, bus=%u baud=%u\r\n",
            (unsigned int)BRIDGE_UART_BUS,
            (unsigned int)BRIDGE_UART_BAUDRATE);
    }
    return ret;
}

static void Atlas_Bridge_Uart_Reset(void)
{
    Atlas_Bridge_Lock_Uart();
    (void)uapi_uart_deinit(BRIDGE_UART_BUS);
    g_bridge_ready = false;
    Atlas_Bridge_Unlock_Uart();
}

static errcode_t Atlas_Bridge_Ensure_Uart_Ready(void)
{
    errcode_t ret;

    if (g_bridge_ready) {
        return ERRCODE_SUCC;
    }

    Atlas_Bridge_Lock_Uart();
    ret = g_bridge_ready ? ERRCODE_SUCC : Atlas_Bridge_Uart_Init();
    Atlas_Bridge_Unlock_Uart();
    return ret;
}

static void Atlas_Bridge_Worker(void *arg)
{
    bridge_packet_t packet;
    (void)arg;

    while (1) {
        if (Atlas_Bridge_Ensure_Uart_Ready() != ERRCODE_SUCC) {
            printf("[Atlas Bridge] UART 初始化失败，等待重试\r\n");
            osDelay(BRIDGE_UART_RETRY_DELAY_MS);
            continue;
        }

        if (osMessageQueueGet(g_bridge_queue, &packet, NULL, BRIDGE_QUEUE_WAIT_MS) != osOK) {
            continue;
        }

        if (Atlas_Bridge_Write_Raw(packet.data, packet.len) != 0) {
            printf("[Atlas Bridge] UART 转发失败，等待重连\r\n");
            osDelay(BRIDGE_UART_RETRY_DELAY_MS);
        }
    }
}

static void Atlas_Bridge_Status_Thread(void *arg)
{
    (void)arg;

    while (1) {
        if (Atlas_Bridge_Ensure_Uart_Ready() == ERRCODE_SUCC) {
            Atlas_Bridge_Send_Discovery_Status();
        }
        osDelay(BRIDGE_STATUS_REPORT_INTERVAL_MS);
    }
}

static void Atlas_Bridge_Rx_Thread(void *arg)
{
    uint8_t read_buffer[BRIDGE_UART_READ_CHUNK_SIZE] = {0};
    uint8_t ctrl_buffer[BRIDGE_UART_CONTROL_BUFFER_SIZE] = {0};
    uint16_t ctrl_buffer_len = 0;
    (void)arg;

    while (1) {
        int32_t read_len;

        if (Atlas_Bridge_Ensure_Uart_Ready() != ERRCODE_SUCC) {
            osDelay(BRIDGE_UART_RETRY_DELAY_MS);
            continue;
        }

        read_len = Atlas_Bridge_Read_Raw(read_buffer, sizeof(read_buffer));
        if (read_len > 0) {
            printf("[Atlas Bridge RX] len=%ld head:", (long)read_len);
            for (int i = 0; i < read_len && i < 32; i++) {
                printf(" %02X", read_buffer[i]);
            }
            printf("\r\n");
            Atlas_Bridge_Parse_Control_Stream(ctrl_buffer, &ctrl_buffer_len, read_buffer, (uint16_t)read_len);
        } else {
            osDelay(BRIDGE_UART_READ_IDLE_DELAY_MS);
        }
    }
}

void Atlas_Bridge_Init(void)
{
    osThreadAttr_t attr = {0};

    if (g_bridge_queue == NULL) {
        g_bridge_queue = osMessageQueueNew(BRIDGE_QUEUE_DEPTH, sizeof(bridge_packet_t), NULL);
    }
    if (g_bridge_uart_mutex == NULL) {
        g_bridge_uart_mutex = osMutexNew(NULL);
    }

    attr.name = "AtlasBridge";
    attr.stack_size = BRIDGE_THREAD_STACK_SIZE;
    attr.priority = BRIDGE_THREAD_PRIORITY;
    if (osThreadNew(Atlas_Bridge_Worker, NULL, &attr) == NULL) {
        printf("[Atlas Bridge] 工作线程创建失败\r\n");
        return;
    }
    attr.name = "AtlasBridgeRx";
    if (osThreadNew(Atlas_Bridge_Rx_Thread, NULL, &attr) == NULL) {
        printf("[Atlas Bridge] 串口接收线程创建失败\r\n");
        return;
    }
    attr.name = "AtlasBridgeStat";
    if (osThreadNew(Atlas_Bridge_Status_Thread, NULL, &attr) == NULL) {
        printf("[Atlas Bridge] 状态线程创建失败\r\n");
        return;
    }

    printf("[Atlas Bridge] 已启动, UART bus=%u baud=%u\r\n",
        (unsigned int)BRIDGE_UART_BUS,
        (unsigned int)BRIDGE_UART_BAUDRATE);
}

bool Atlas_Bridge_Is_Ready(void)
{
    return g_bridge_ready;
}

bool Atlas_Bridge_Enqueue_Packet(const uint8_t *payload, uint16_t len)
{
    bridge_packet_t packet;

    if ((payload == NULL) || (len == 0) || (len > BRIDGE_QUEUE_PACKET_MAX_LEN) || (g_bridge_queue == NULL)) {
        return false;
    }

    packet.len = len;
    (void)memcpy(packet.data, payload, len);
    return osMessageQueuePut(g_bridge_queue, &packet, 0, 0) == osOK;
}
