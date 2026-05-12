#include "sle_module.h"
#include <stdio.h>
#include <string.h>
#include "errcode.h"

// 引入官方真实的底层头文件
#include "sle_common.h"
#include "sle_errcode.h"
#include "sle_device_discovery.h"
#include "sle_connection_manager.h"
#include "sle_ssap_server.h" 

// [新增这一行] 如果底层没有定义默认广播句柄，我们手动指定为 1
#ifndef SLE_ADV_HANDLE_DEFAULT
#define SLE_ADV_HANDLE_DEFAULT 1
#endif

#define SLE_INVALID_CONN_ID 0xFFFF
#define SLE_UUID_LEN_2 2
#define SLE_NAME_MAX_LEN 31
#define JS_SLE_SERVICE_UUID 0x1234
#define JS_SLE_PROPERTY_UUID 0x5678
#define JS_SLE_APP_UUID_LOW 0xAA
#define JS_SLE_APP_UUID_HIGH 0xBB
#define JS_SLE_ADV_TX_POWER 20
#define JS_SLE_SEND_LOG_INTERVAL 10

#define JS_ADV_CHANNEL_MAP_DEFAULT 0x07
#define JS_ADV_DATA_TYPE_DISCOVERY_LEVEL 0x01
#define JS_ADV_DATA_TYPE_COMPLETE_LIST_OF_16BIT_SERVICE_UUIDS 0x05
#define JS_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME 0x0B
#define JS_ADV_DATA_TYPE_TX_POWER_LEVEL 0x0C

static const uint8_t g_sle_uuid_base[SLE_UUID_LEN] = {
    0x37, 0xBE, 0xA8, 0x80, 0xFC, 0x70, 0x11, 0xEA,
    0xB7, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

// --- 全局静态变量 ---
static SLE_ReceiveCallback_t g_receive_cb = NULL; // 应用层回调
static uint8_t  g_sle_server_id = 0;              // 服务端 ID
static uint16_t g_sle_conn_id = SLE_INVALID_CONN_ID;
static uint16_t g_sle_service_handle = 0;         // Service 句柄
static uint16_t g_sle_property_handle = 0;        // Property 句柄
static uint32_t g_send_success_count = 0;
static uint8_t g_sle_property_value[2] = {0x00, 0x00};
static uint8_t g_sle_notify_descriptor_value[2] = {0x01, 0x00};
static uint8_t g_sle_enabled = 0;
static uint8_t g_adv_pending = 0;
static char g_device_name[SLE_NAME_MAX_LEN + 1] = {0};
static uint8_t g_adv_data[8] = {0};
static uint8_t g_scan_rsp_data[SLE_NAME_MAX_LEN + 5] = {0};

static void SLE_Set_Uuid16(uint16_t uuid16, sle_uuid_t *uuid)
{
    if (uuid == NULL) {
        return;
    }

    (void)memset(uuid, 0, sizeof(*uuid));
    (void)memcpy(uuid->uuid, g_sle_uuid_base, sizeof(g_sle_uuid_base));
    uuid->len = SLE_UUID_LEN_2;
    uuid->uuid[14] = (uint8_t)(uuid16 & 0xFF);
    uuid->uuid[15] = (uint8_t)((uuid16 >> 8) & 0xFF);
}

static void SLE_Log_Address(const char *prefix, const sle_addr_t *addr)
{
    if (prefix == NULL || addr == NULL) {
        return;
    }

    printf("%s %02X:**:**:**:%02X:%02X\r\n",
        prefix,
        addr->addr[0],
        addr->addr[4],
        addr->addr[5]);
}

static void SLE_Log_Result(const char *step, errcode_t ret)
{
    if (step == NULL) {
        return;
    }

    printf("[SLE] %s -> ret=0x%lx\r\n", step, (unsigned long)ret);
}

static errcode_t SLE_Start_Advertising_Internal(void)
{
    errcode_t ret;
    sle_announce_param_t adv_param = {0};
    sle_announce_data_t adv_data = {0};
    size_t name_len;
    uint16_t scan_rsp_len = 0;

    if (!g_sle_enabled || g_device_name[0] == '\0') {
        return ERRCODE_FAIL;
    }

    name_len = strlen(g_device_name);
    if (name_len > SLE_NAME_MAX_LEN) {
        name_len = SLE_NAME_MAX_LEN;
    }

    ret = sle_set_local_name((const uint8_t *)g_device_name, (uint8_t)(name_len + 1));
    SLE_Log_Result("sle_set_local_name", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    adv_param.announce_handle = SLE_ADV_HANDLE_DEFAULT;
    adv_param.announce_mode = SLE_ANNOUNCE_MODE_CONNECTABLE_SCANABLE;
    adv_param.announce_gt_role = SLE_ANNOUNCE_ROLE_T_CAN_NEGO;
    adv_param.announce_level = SLE_ANNOUNCE_LEVEL_NORMAL;
    adv_param.announce_interval_min = 32;
    adv_param.announce_interval_max = 64;
    adv_param.announce_channel_map = JS_ADV_CHANNEL_MAP_DEFAULT;
    adv_param.announce_tx_power = JS_SLE_ADV_TX_POWER;
    adv_param.conn_interval_min = 0x14;
    adv_param.conn_interval_max = 0x14;
    adv_param.conn_max_latency = 0x1F3;
    adv_param.conn_supervision_timeout = 0x1F4;

    ret = sle_set_announce_param(SLE_ADV_HANDLE_DEFAULT, &adv_param);
    SLE_Log_Result("sle_set_announce_param", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    g_adv_data[0] = JS_ADV_DATA_TYPE_DISCOVERY_LEVEL;
    g_adv_data[1] = 1;
    g_adv_data[2] = SLE_ANNOUNCE_LEVEL_NORMAL;
    g_adv_data[3] = JS_ADV_DATA_TYPE_COMPLETE_LIST_OF_16BIT_SERVICE_UUIDS;
    g_adv_data[4] = 2;
    g_adv_data[5] = (uint8_t)(JS_SLE_SERVICE_UUID & 0xFF);
    g_adv_data[6] = (uint8_t)((JS_SLE_SERVICE_UUID >> 8) & 0xFF);

    g_scan_rsp_data[scan_rsp_len++] = JS_ADV_DATA_TYPE_TX_POWER_LEVEL;
    g_scan_rsp_data[scan_rsp_len++] = 1;
    g_scan_rsp_data[scan_rsp_len++] = JS_SLE_ADV_TX_POWER;
    g_scan_rsp_data[scan_rsp_len++] = JS_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME;
    g_scan_rsp_data[scan_rsp_len++] = (uint8_t)name_len;
    (void)memcpy(&g_scan_rsp_data[scan_rsp_len], g_device_name, name_len);
    scan_rsp_len = (uint16_t)(scan_rsp_len + name_len);

    adv_data.announce_data = g_adv_data;
    adv_data.announce_data_len = 7;
    adv_data.seek_rsp_data = g_scan_rsp_data;
    adv_data.seek_rsp_data_len = scan_rsp_len;

    ret = sle_set_announce_data(SLE_ADV_HANDLE_DEFAULT, &adv_data);
    SLE_Log_Result("sle_set_announce_data", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    ret = sle_start_announce(SLE_ADV_HANDLE_DEFAULT);
    SLE_Log_Result("sle_start_announce", ret);
    if (ret == ERRCODE_SUCC) {
        printf("[SLE] 广播启动请求已发出, 设备名:%s\r\n", g_device_name);
    }
    return ret;
}

// ==========================================
// 1. 底层回调函数区 (签名严格遵守官方示例)
// ==========================================

// 读请求回调 (必须提供给底层，即使我们用不到)
static void ssaps_read_request_cbk(uint8_t server_id, uint16_t conn_id, ssaps_req_read_cb_t *read_cb_para, errcode_t status) {
    (void)read_cb_para;
    printf("[SLE] 收到读请求 server:%u conn:%u status:0x%lx\r\n",
        server_id,
        conn_id,
        (unsigned long)status);
}

// 写请求回调 (主设备发数据过来)
static void ssaps_write_request_cbk(uint8_t server_id, uint16_t conn_id, ssaps_req_write_cb_t *write_cb_para, errcode_t status) {
    errcode_t ret;
    ssaps_send_rsp_t rsp = {0};
    
    if (write_cb_para != NULL && write_cb_para->value != NULL) {
        printf("[SLE] 收到写请求 server:%u conn:%u handle:%u len:%u need_rsp:%u status:0x%lx payload:%.*s\r\n",
            server_id,
            conn_id,
            write_cb_para->handle,
            write_cb_para->length,
            write_cb_para->need_rsp,
            (unsigned long)status,
            (int)write_cb_para->length,
            (const char *)write_cb_para->value);
        if (g_receive_cb != NULL) {
            g_receive_cb(write_cb_para->value, write_cb_para->length);
        }

        if (write_cb_para->need_rsp) {
            rsp.request_id = write_cb_para->request_id;
            rsp.status = ERRCODE_SLE_SUCCESS;
            rsp.value_len = 0;
            rsp.value = NULL;
            ret = ssaps_send_response(server_id, conn_id, &rsp);
            SLE_Log_Result("ssaps_send_response", ret);
        }
    }
}

// 建立或断开连接时的回调
static void sle_connect_state_changed_cbk(uint16_t conn_id, const sle_addr_t *addr, sle_acb_state_t conn_state, sle_pair_state_t pair_state, sle_disc_reason_t disc_reason) {
    printf("[SLE] 连接状态变化 conn:%u state:%u pair:%u reason:%u\r\n",
        conn_id,
        conn_state,
        pair_state,
        disc_reason);
    SLE_Log_Address("[SLE] 对端地址:", addr);
    
    if (conn_state == SLE_ACB_STATE_CONNECTED) {
        printf("[SLE] ⚡ 主设备已连接! Conn_ID: %d\r\n", conn_id);
        g_sle_conn_id = conn_id; 
    } 
    else if (conn_state == SLE_ACB_STATE_DISCONNECTED) {
        printf("[SLE] ❌ 主设备已断开!\r\n");
        g_sle_conn_id = SLE_INVALID_CONN_ID;
        if (g_adv_pending) {
            (void)SLE_Start_Advertising_Internal();
        }
    }
}

static void sle_announce_enable_cbk(uint32_t announce_id, errcode_t status)
{
    printf("[SLE] 广播已使能 announce_id:%lu status:0x%lx\r\n",
        (unsigned long)announce_id,
        (unsigned long)status);
}

static void sle_announce_disable_cbk(uint32_t announce_id, errcode_t status)
{
    printf("[SLE] 广播已关闭 announce_id:%lu status:0x%lx\r\n",
        (unsigned long)announce_id,
        (unsigned long)status);
}

static void sle_announce_terminal_cbk(uint32_t announce_id)
{
    printf("[SLE] 广播终止 announce_id:%lu\r\n", (unsigned long)announce_id);
}

// ==========================================
// 2. 核心：构建星闪服务树
// ==========================================
static errcode_t SLE_Add_Service_And_Property(void)
{
    errcode_t ret;
    sle_uuid_t app_uuid = {0};
    sle_uuid_t service_uuid = {0};
    ssaps_property_info_t property = {0};
    ssaps_desc_info_t descriptor = {0};

    app_uuid.len = SLE_UUID_LEN_2;
    app_uuid.uuid[0] = JS_SLE_APP_UUID_LOW;
    app_uuid.uuid[1] = JS_SLE_APP_UUID_HIGH;
    ret = ssaps_register_server(&app_uuid, &g_sle_server_id);
    SLE_Log_Result("ssaps_register_server", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    SLE_Set_Uuid16(JS_SLE_SERVICE_UUID, &service_uuid);
    ret = ssaps_add_service_sync(g_sle_server_id, &service_uuid, 1, &g_sle_service_handle);
    SLE_Log_Result("ssaps_add_service_sync", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    SLE_Set_Uuid16(JS_SLE_PROPERTY_UUID, &property.uuid);
    property.permissions = SSAP_PERMISSION_READ | SSAP_PERMISSION_WRITE;
    property.operate_indication = SSAP_OPERATE_INDICATION_BIT_READ |
        SSAP_OPERATE_INDICATION_BIT_WRITE |
        SSAP_OPERATE_INDICATION_BIT_WRITE_NO_RSP |
        SSAP_OPERATE_INDICATION_BIT_NOTIFY;
    property.value = g_sle_property_value;
    property.value_len = sizeof(g_sle_property_value);

    ret = ssaps_add_property_sync(g_sle_server_id, g_sle_service_handle, &property, &g_sle_property_handle);
    SLE_Log_Result("ssaps_add_property_sync", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    descriptor.permissions = SSAP_PERMISSION_READ | SSAP_PERMISSION_WRITE;
    descriptor.operate_indication = SSAP_OPERATE_INDICATION_BIT_READ |
        SSAP_OPERATE_INDICATION_BIT_WRITE;
    descriptor.type = SSAP_DESCRIPTOR_USER_DESCRIPTION;
    descriptor.value = g_sle_notify_descriptor_value;
    descriptor.value_len = sizeof(g_sle_notify_descriptor_value);
    ret = ssaps_add_descriptor_sync(g_sle_server_id, g_sle_service_handle, g_sle_property_handle, &descriptor);
    SLE_Log_Result("ssaps_add_descriptor_sync", ret);
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    ret = ssaps_start_service(g_sle_server_id, g_sle_service_handle);
    SLE_Log_Result("ssaps_start_service", ret);
    if (ret == ERRCODE_SUCC) {
        printf("[SLE] 服务树创建完成 server:%u service_handle:%u property_handle:%u\r\n",
            g_sle_server_id,
            g_sle_service_handle,
            g_sle_property_handle);
    }
    return ret;
}

static void sle_enable_cbk(errcode_t status)
{
    printf("[SLE] 协议栈使能回调 status:0x%lx\r\n", (unsigned long)status);
    if (status != ERRCODE_SUCC) {
        return;
    }

    g_sle_enabled = 1;
    if (SLE_Add_Service_And_Property() != ERRCODE_SUCC) {
        printf("[SLE] 服务树初始化失败\r\n");
        return;
    }

    if (g_adv_pending) {
        (void)SLE_Start_Advertising_Internal();
    }
}

// ==========================================
// 3. 对外暴露的 API (供 js_main.c 调用)
// ==========================================

void SLE_Register_Receive_Callback(SLE_ReceiveCallback_t cb) {
    g_receive_cb = cb;
}


void SLE_Server_Init(void) {
    errcode_t ret;
    sle_announce_seek_callbacks_t announce_cbks = {0};
    sle_connection_callbacks_t conn_cbks = {0};
    ssaps_callbacks_t ssaps_cbk = {0};

    announce_cbks.sle_enable_cb = sle_enable_cbk;
    announce_cbks.announce_enable_cb = sle_announce_enable_cbk;
    announce_cbks.announce_disable_cb = sle_announce_disable_cbk;
    announce_cbks.announce_terminal_cb = sle_announce_terminal_cbk;
    ret = sle_announce_seek_register_callbacks(&announce_cbks);
    SLE_Log_Result("sle_announce_seek_register_callbacks", ret);

    conn_cbks.connect_state_changed_cb = sle_connect_state_changed_cbk;
    ret = sle_connection_register_callbacks(&conn_cbks);
    SLE_Log_Result("sle_connection_register_callbacks", ret);

    ssaps_cbk.read_request_cb = ssaps_read_request_cbk; 
    ssaps_cbk.write_request_cb = ssaps_write_request_cbk;
    ret = ssaps_register_callbacks(&ssaps_cbk);
    SLE_Log_Result("ssaps_register_callbacks", ret);

    ret = enable_sle();
    SLE_Log_Result("enable_sle", ret);
}

void SLE_Start_Advertising(const char* device_name) {
    size_t name_len;

    if (device_name == NULL) {
        return;
    }

    name_len = strlen(device_name);
    if (name_len > SLE_NAME_MAX_LEN) {
        name_len = SLE_NAME_MAX_LEN;
    }

    (void)memcpy(g_device_name, device_name, name_len);
    g_device_name[name_len] = '\0';
    g_adv_pending = 1;

    printf("[SLE] 已记录广播名称:%s\r\n", g_device_name);
    if (g_sle_enabled) {
        (void)SLE_Start_Advertising_Internal();
    } else {
        printf("[SLE] 协议栈尚未使能完成，广播将在回调中启动\r\n");
    }
}

bool SLE_IsConnected(void)
{
    return (g_sle_conn_id != SLE_INVALID_CONN_ID);
}

int SLE_Send_Data(uint8_t *payload, uint16_t len) {
    errcode_t ret;
    ssaps_ntf_ind_t send_param = {0};

    if (payload == NULL || len == 0 || g_sle_conn_id == 0xFFFF) {
        return -1; 
    }

    send_param.handle = g_sle_property_handle;
    send_param.type = SSAP_PROPERTY_TYPE_VALUE;
    send_param.value = payload;
    send_param.value_len = len;

    ret = ssaps_notify_indicate(g_sle_server_id, g_sle_conn_id, &send_param);
    
    if (ret != ERRCODE_SUCC) {
        SLE_Log_Result("ssaps_notify_indicate", ret);
        return -1;
    }

    g_send_success_count++;
    if ((g_send_success_count % JS_SLE_SEND_LOG_INTERVAL) == 0) {
        printf("[SLE] 已成功发送 %lu 包, 最近负载长度:%u 字节\r\n",
            (unsigned long)g_send_success_count,
            (unsigned int)len);
    }
    
    return 0; // 发送成功
}
