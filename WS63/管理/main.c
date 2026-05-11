#include <stdio.h>
#include <string.h>
#include "cmsis_os2.h"
#include "app_init.h"
#include "atlas_bridge.h"
#include "js_master_target_config.h"
#include "sle_client_module.h"

static bool g_start_command_sent = false;

static void On_JS_Slave_Report(const uint8_t *data, uint16_t len)
{
    if (!Atlas_Bridge_Enqueue_Packet(data, len)) {
        printf("[JS Master] 上报包转发入队失败 len:%u\r\n", len);
    }
}

// static void JS_Master_Task(void *arg)
// {
//     bool last_ready = false;

//     (void)arg;
//     printf("\r\n=======================================\r\n");
//     printf("[JS Master] 主设备客户端启动...\r\n");
//     printf("=======================================\r\n");

//     Atlas_Bridge_Init();
//     SLE_Client_Register_Notify_Callback(On_JS_Slave_Report);
//     SLE_Client_Init();
//     SLE_Client_Start(JS_MASTER_SELECTED_TARGET_NAME);

//     while (1) {
//         if (SLE_Client_Is_Ready()) {
//             if (!last_ready) {
//                 printf("[JS Master] SLE 链路已就绪\r\n");
//                 last_ready = true;
//                 g_start_command_sent = false;
//             }

//             if (!g_start_command_sent) {
//                 static const char *start_cmd = "START";
//                 if (SLE_Client_Send_Command((uint8_t *)start_cmd, (uint16_t)strlen(start_cmd)) == 0) {
//                     g_start_command_sent = true;
//                     printf("[JS Master] 已下发 START，准备转发模型包\r\n");
//                 }
//             }

//             if (Atlas_Bridge_Is_Ready()) {
//                 osDelay(20);
//             } else {
//                 osDelay(100);
//             }
//             continue;
//         }

//         if (last_ready) {
//             printf("[JS Master] SLE 链路已断开，等待重连\r\n");
//             last_ready = false;
//             g_start_command_sent = false;
//         }
//         osDelay(100);
//     }
// }
static void JS_Master_Task(void *arg)
{
    bool last_ready = false;
    uint32_t debug_counter = 0; // 新增：调试计数器

    (void)arg;
    printf("\r\n=======================================\r\n");
    printf("[JS Master] 主设备客户端启动 (带 PC 调试模式)...\r\n");
    printf("=======================================\r\n");

    Atlas_Bridge_Init();
    SLE_Client_Register_Notify_Callback(On_JS_Slave_Report);
    SLE_Client_Init();
    SLE_Client_Start(JS_MASTER_SELECTED_TARGET_NAME);

    while (1) {
        debug_counter++;

        // ==========================================
        // 【新增调试功能】：每 2 秒 (20 * 100ms) 触发一次
        // ==========================================
        if (debug_counter % 20 == 0) {
            // 1. 打印当前真实状态，方便在 PC 端观察
            printf("[DEBUG] 系统存活! 星闪连接状态: %s\r\n", 
                   SLE_Client_Is_Ready() ? "已连接" : "未连接/寻找中...");

            // 2. 如果星闪没连上，强行制造一个“假业务包”测试 UART 链路
            if (!SLE_Client_Is_Ready()) {
                // 构造一个假的包：包头 4D 43 (MC) 或 4A 53 (JS)，这里随便造几个字节
                uint8_t mock_packet[] = {0x4A, 0x53, 0x00, 0x01, 0xFF, 0xEE};
                if (Atlas_Bridge_Enqueue_Packet(mock_packet, sizeof(mock_packet))) {
                    printf("[DEBUG] 已强行压入一个模拟测试包，请在 PC 串口助手查看 HEX 输出!\r\n");
                }
            }
        }
        // ==========================================

        if (SLE_Client_Is_Ready()) {
            if (!last_ready) {
                printf("[JS Master] SLE 链路已就绪\r\n");
                last_ready = true;
                g_start_command_sent = false;
            }

            if (!g_start_command_sent) {
                static const char *start_cmd = "START";
                if (SLE_Client_Send_Command((uint8_t *)start_cmd, (uint16_t)strlen(start_cmd)) == 0) {
                    g_start_command_sent = true;
                    printf("[JS Master] 已下发 START，准备转发真实模型包\r\n");
                }
            }

            if (Atlas_Bridge_Is_Ready()) {
                osDelay(20);
            } else {
                osDelay(100);
            }
            continue;
        }

        if (last_ready) {
            printf("[JS Master] SLE 链路已断开，等待重连\r\n");
            last_ready = false;
            g_start_command_sent = false;
        }
        osDelay(100);
    }
}
static void JS_Master_Entry(void)
{
    osThreadAttr_t attr = {0};

    attr.name = "JS_MasterTask";
    attr.stack_size = 1024 * 8;
    attr.priority = osPriorityNormal;

    if (osThreadNew(JS_Master_Task, NULL, &attr) == NULL) {
        printf("[JS Master] 线程创建失败!\r\n");
    }
}

app_run(JS_Master_Entry);
