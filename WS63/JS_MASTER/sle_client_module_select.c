#include "sle_client_module.h"

#include <stdbool.h>
#include <stdio.h>
#include <string.h>

#include "errcode.h"
#include "sle_common.h"
#include "sle_connection_manager.h"
#include "sle_device_discovery.h"
#include "sle_errcode.h"
#include "sle_ssap_client.h"

#define SLE_INVALID_CONN_ID 0xFFFF
#define SLE_INVALID_CLIENT_ID 0xFF
#define SLE_UUID_LEN_2 2
#define SLE_NAME_MAX_LEN 31
#define JS_SLE_SERVICE_UUID 0x1234
#define JS_SLE_PROPERTY_UUID 0x5678
#define JS_SLE_SERVICE_UUID_LOW 0x34
#define JS_SLE_SERVICE_UUID_HIGH 0x12
#define JS_CLIENT_APP_UUID_LOW 0xCC
#define JS_CLIENT_APP_UUID_HIGH 0xDD
#define JS_SCAN_INTERVAL 100
#define JS_SCAN_WINDOW 100
#define JS_CONN_INTERVAL 0x14
#define JS_CONN_TIMEOUT 0x1F4
#define JS_DISCOVERY_START_HANDLE 1
#define JS_DISCOVERY_END_HANDLE 0xFFFF

#define JS_ADV_DATA_TYPE_COMPLETE_LIST_OF_16BIT_SERVICE_UUIDS 0x05
#define JS_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME 0x0B
#define JS_DISCOVERED_NODE_MAX 8
#define JS_NODE_NAME_PREFIX "WS63_JS_Node_"
#define JS_NODE_FALLBACK_PREFIX "JS_Node_"

typedef enum {
    JS_DISCOVERY_IDLE = 0,
    JS_DISCOVERY_SERVICE,
    JS_DISCOVERY_PROPERTY,
} JS_DiscoveryState_t;

typedef struct {
    bool in_use;
    sle_addr_t addr;
    int8_t rssi;
    bool has_service;
    char name[SLE_NAME_MAX_LEN + 1];
} JS_DiscoveredNode_t;

static const uint8_t g_sle_uuid_base[SLE_UUID_LEN] = {
    0x37, 0xBE, 0xA8, 0x80, 0xFC, 0x70, 0x11, 0xEA,
    0xB7, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
};

static SLE_ClientNotifyCallback_t g_notify_cb = NULL;
static sle_announce_seek_callbacks_t g_seek_cbks = {0};
static sle_connection_callbacks_t g_conn_cbks = {0};
static ssapc_callbacks_t g_ssapc_cbks = {0};
static sle_addr_t g_target_addr = {0};
static uint8_t g_client_id = SLE_INVALID_CLIENT_ID;
static uint16_t g_conn_id = SLE_INVALID_CONN_ID;
static uint16_t g_service_start_handle = 0;
static uint16_t g_service_end_handle = 0;
static uint16_t g_property_handle = 0;
static bool g_sle_enabled = false;
static bool g_target_found = false;
static bool g_target_connected = false;
static bool g_target_selected = false;
static JS_DiscoveryState_t g_discovery_state = JS_DISCOVERY_IDLE;
static char g_target_name[SLE_NAME_MAX_LEN + 1] = {0};
static JS_DiscoveredNode_t g_discovered_nodes[JS_DISCOVERED_NODE_MAX] = {0};

static void SLE_Client_Log_Address(const char *prefix, const sle_addr_t *addr)
{
    if (prefix == NULL || addr == NULL) {
        return;
    }
    printf("%s %02X:**:**:**:%02X:%02X\r\n", prefix, addr->addr[0], addr->addr[4], addr->addr[5]);
}

static void SLE_Client_Log_Result(const char *step, errcode_t ret)
{
    if (step == NULL) {
        return;
    }
    printf("[JS Master] %s -> ret=0x%lx\r\n", step, (unsigned long)ret);
}

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

static bool SLE_Uuid_Equals_U16(const sle_uuid_t *uuid, uint16_t expected)
{
    if (uuid == NULL || uuid->len != SLE_UUID_LEN_2) {
        return false;
    }
    if ((uuid->uuid[14] == (uint8_t)(expected & 0xFF)) &&
        (uuid->uuid[15] == (uint8_t)((expected >> 8) & 0xFF))) {
        return true;
    }
    return (uuid->uuid[0] == (uint8_t)(expected & 0xFF)) &&
        (uuid->uuid[1] == (uint8_t)((expected >> 8) & 0xFF));
}

static bool SLE_Name_Has_Node_Prefix(const char *name)
{
    size_t prefix_len;
    if (name == NULL) {
        return false;
    }
    prefix_len = strlen(JS_NODE_NAME_PREFIX);
    return strncmp(name, JS_NODE_NAME_PREFIX, prefix_len) == 0;
}

static void SLE_Client_Make_Fallback_Name(const sle_addr_t *addr, char *name_out, uint8_t name_out_size)
{
    if (addr == NULL || name_out == NULL || name_out_size == 0) {
        return;
    }
    (void)snprintf(name_out, name_out_size, "%s%02X%02X", JS_NODE_FALLBACK_PREFIX, addr->addr[4], addr->addr[5]);
}

static bool SLE_Adv_Data_Parse_Node(const uint8_t *data, uint8_t data_len, char *name_out,
    uint8_t name_out_size, bool *has_service_out)
{
    uint8_t offset = 0;
    bool has_service = false;
    bool has_name = false;

    if ((name_out == NULL) || (name_out_size == 0) || (has_service_out == NULL)) {
        return false;
    }
    name_out[0] = '\0';

    while ((data != NULL) && (offset + 2 <= data_len)) {
        uint8_t type = data[offset++];
        uint8_t len = data[offset++];
        if (offset + len > data_len) {
            break;
        }

        if (type == JS_ADV_DATA_TYPE_COMPLETE_LIST_OF_16BIT_SERVICE_UUIDS && len >= 2) {
            for (uint8_t index = 0; (index + 1) < len; index = (uint8_t)(index + 2)) {
                if ((data[offset + index] == JS_SLE_SERVICE_UUID_LOW) &&
                    (data[offset + index + 1] == JS_SLE_SERVICE_UUID_HIGH)) {
                    has_service = true;
                    break;
                }
            }
        }

        if ((type == JS_ADV_DATA_TYPE_COMPLETE_LOCAL_NAME) && (len > 0)) {
            uint8_t copy_len = (len >= name_out_size) ? (name_out_size - 1) : len;
            (void)memcpy(name_out, &data[offset], copy_len);
            name_out[copy_len] = '\0';
            has_name = true;
        }

        offset = (uint8_t)(offset + len);
    }

    *has_service_out = has_service;
    return has_service || (has_name && SLE_Name_Has_Node_Prefix(name_out));
}

static int SLE_Client_Find_Node_By_Name(const char *name)
{
    if (name == NULL || name[0] == '\0') {
        return -1;
    }
    for (int index = 0; index < JS_DISCOVERED_NODE_MAX; index++) {
        if (g_discovered_nodes[index].in_use && strcmp(g_discovered_nodes[index].name, name) == 0) {
            return index;
        }
    }
    return -1;
}

static void SLE_Client_Record_Discovered_Node(const sle_addr_t *addr, const char *name, bool has_service, int8_t rssi)
{
    int empty_index = -1;
    int target_index = -1;
    char stable_name[SLE_NAME_MAX_LEN + 1] = {0};

    if (addr == NULL) {
        return;
    }

    if (name != NULL && name[0] != '\0') {
        (void)snprintf(stable_name, sizeof(stable_name), "%s", name);
    } else {
        SLE_Client_Make_Fallback_Name(addr, stable_name, sizeof(stable_name));
    }

    for (int index = 0; index < JS_DISCOVERED_NODE_MAX; index++) {
        if (!g_discovered_nodes[index].in_use) {
            if (empty_index < 0) {
                empty_index = index;
            }
            continue;
        }
        if (memcmp(g_discovered_nodes[index].addr.addr, addr->addr, sizeof(addr->addr)) == 0) {
            target_index = index;
            break;
        }
    }

    if ((target_index < 0) && (empty_index >= 0)) {
        target_index = empty_index;
        g_discovered_nodes[target_index].in_use = true;
        g_discovered_nodes[target_index].addr = *addr;
        printf("[JS Master] 发现节点 slot=%d name=%s rssi=%d\r\n", target_index, stable_name, rssi);
    }

    if (target_index < 0) {
        return;
    }

    g_discovered_nodes[target_index].rssi = rssi;
    g_discovered_nodes[target_index].has_service = has_service;
    (void)snprintf(g_discovered_nodes[target_index].name, sizeof(g_discovered_nodes[target_index].name), "%s", stable_name);
}

static void SLE_Client_Reset_Link_State(void)
{
    g_conn_id = SLE_INVALID_CONN_ID;
    g_target_connected = false;
    g_service_start_handle = 0;
    g_service_end_handle = 0;
    g_property_handle = 0;
    g_discovery_state = JS_DISCOVERY_IDLE;
}

static errcode_t SLE_Client_Request_Exchange_Info(void)
{
    errcode_t ret;
    ssap_exchange_info_t info = {0};
    info.mtu_size = 500;
    info.version = 1;
    ret = ssapc_exchange_info_req(g_client_id, g_conn_id, &info);
    SLE_Client_Log_Result("ssapc_exchange_info_req", ret);
    return ret;
}

static errcode_t SLE_Client_Start_Service_Discovery(void)
{
    errcode_t ret;
    ssapc_find_structure_param_t find_param = {0};
    g_discovery_state = JS_DISCOVERY_SERVICE;
    find_param.type = SSAP_FIND_TYPE_PRIMARY_SERVICE;
    find_param.start_hdl = JS_DISCOVERY_START_HANDLE;
    find_param.end_hdl = JS_DISCOVERY_END_HANDLE;
    SLE_Set_Uuid16(JS_SLE_SERVICE_UUID, &find_param.uuid);
    ret = ssapc_find_structure(g_client_id, g_conn_id, &find_param);
    SLE_Client_Log_Result("ssapc_find_structure(service)", ret);
    return ret;
}

static errcode_t SLE_Client_Start_Property_Discovery(void)
{
    errcode_t ret;
    ssapc_find_structure_param_t find_param = {0};
    g_discovery_state = JS_DISCOVERY_PROPERTY;
    find_param.type = SSAP_FIND_TYPE_PROPERTY;
    find_param.start_hdl = g_service_start_handle;
    find_param.end_hdl = g_service_end_handle;
    SLE_Set_Uuid16(JS_SLE_PROPERTY_UUID, &find_param.uuid);
    ret = ssapc_find_structure(g_client_id, g_conn_id, &find_param);
    SLE_Client_Log_Result("ssapc_find_structure(property)", ret);
    return ret;
}

static void SLE_Client_Start_Scan_Internal(void)
{
    errcode_t ret;
    sle_seek_param_t param = {0};

    if (!g_sle_enabled) {
        return;
    }

    g_target_found = false;
    param.own_addr_type = 0;
    param.filter_duplicates = 0;
    param.seek_filter_policy = 0;
    param.seek_phys = 1;
    param.seek_type[0] = 0;
    param.seek_interval[0] = JS_SCAN_INTERVAL;
    param.seek_window[0] = JS_SCAN_WINDOW;

    ret = sle_set_seek_param(&param);
    SLE_Client_Log_Result("sle_set_seek_param", ret);
    if (ret != ERRCODE_SUCC) {
        return;
    }
    ret = sle_start_seek();
    SLE_Client_Log_Result("sle_start_seek", ret);
}

static void SLE_Client_Connect_Selected_Node(int node_index)
{
    if (node_index < 0 || node_index >= JS_DISCOVERED_NODE_MAX || !g_discovered_nodes[node_index].in_use) {
        printf("[JS Master] 未找到前端选择的目标:%s，继续扫描\r\n", g_target_name);
        SLE_Client_Start_Scan_Internal();
        return;
    }

    g_target_found = true;
    g_target_addr = g_discovered_nodes[node_index].addr;
    printf("[JS Master] 前端已选择目标:%s，准备连接\r\n", g_target_name);
    SLE_Client_Log_Address("[JS Master] 目标地址:", &g_target_addr);
    SLE_Client_Log_Result("sle_stop_seek", sle_stop_seek());
}

static void SLE_Client_Try_Connect_Selected_Target(void)
{
    int index;
    if (!g_target_selected || g_target_name[0] == '\0' || g_target_connected) {
        return;
    }
    index = SLE_Client_Find_Node_By_Name(g_target_name);
    if (index >= 0) {
        SLE_Client_Connect_Selected_Node(index);
    } else if (g_sle_enabled) {
        SLE_Client_Start_Scan_Internal();
    }
}

static void SLE_Client_Enable_Callback(errcode_t status)
{
    errcode_t ret;
    sle_addr_t local_address = {0};
    sle_default_connect_param_t param = {0};
    sle_uuid_t app_uuid = {0};

    printf("[JS Master] 协议栈使能回调 status:0x%lx\r\n", (unsigned long)status);
    if (status != ERRCODE_SUCC) {
        return;
    }

    g_sle_enabled = true;
    local_address.type = 0;
    local_address.addr[0] = 0x13;
    local_address.addr[1] = 0x67;
    local_address.addr[2] = 0x5C;
    local_address.addr[3] = 0x07;
    local_address.addr[4] = 0x00;
    local_address.addr[5] = 0x52;
    ret = sle_set_local_addr(&local_address);
    SLE_Client_Log_Result("sle_set_local_addr", ret);

    param.enable_filter_policy = 0;
    param.gt_negotiate = SLE_ANNOUNCE_ROLE_G_CAN_NEGO;
    param.initiate_phys = 1;
    param.max_interval = JS_CONN_INTERVAL;
    param.min_interval = JS_CONN_INTERVAL;
    param.scan_interval = 400;
    param.scan_window = 20;
    param.timeout = JS_CONN_TIMEOUT;
    ret = sle_default_connection_param_set(&param);
    SLE_Client_Log_Result("sle_default_connection_param_set", ret);

    app_uuid.len = SLE_UUID_LEN_2;
    app_uuid.uuid[0] = JS_CLIENT_APP_UUID_LOW;
    app_uuid.uuid[1] = JS_CLIENT_APP_UUID_HIGH;
    ret = ssapc_register_client(&app_uuid, &g_client_id);
    SLE_Client_Log_Result("ssapc_register_client", ret);
    if (ret != ERRCODE_SUCC) {
        return;
    }

    printf("[JS Master] 前端选择模式：仅扫描并上报设备列表，等待 Atlas 下发 SELECT_TARGET\r\n");
    SLE_Client_Start_Scan_Internal();
}

static void SLE_Client_Seek_Enable_Callback(errcode_t status)
{
    printf("[JS Master] 扫描已启动 status:0x%lx\r\n", (unsigned long)status);
}

static void SLE_Client_Seek_Disable_Callback(errcode_t status)
{
    errcode_t ret;
    printf("[JS Master] 扫描已停止 status:0x%lx selected:%u found:%u\r\n",
        (unsigned long)status, g_target_selected ? 1 : 0, g_target_found ? 1 : 0);

    if ((status != ERRCODE_SUCC) || !g_target_found || !g_target_selected) {
        if (g_sle_enabled && !g_target_connected) {
            SLE_Client_Start_Scan_Internal();
        }
        return;
    }

    ret = sle_connect_remote_device(&g_target_addr);
    SLE_Client_Log_Result("sle_connect_remote_device", ret);
}

static void SLE_Client_Seek_Result_Callback(sle_seek_result_info_t *seek_result_data)
{
    char discovered_name[SLE_NAME_MAX_LEN + 1] = {0};
    bool has_service = false;

    if (seek_result_data == NULL) {
        return;
    }

    if (!SLE_Adv_Data_Parse_Node(seek_result_data->data, seek_result_data->data_length,
        discovered_name, sizeof(discovered_name), &has_service)) {
        return;
    }

    SLE_Client_Record_Discovered_Node(&seek_result_data->addr, discovered_name, has_service,
        (int8_t)seek_result_data->rssi);

    if (!g_target_selected || g_target_name[0] == '\0') {
        return;
    }

    if (strcmp(g_discovered_nodes[SLE_Client_Find_Node_By_Name(g_target_name)].name, g_target_name) == 0) {
        int index = SLE_Client_Find_Node_By_Name(g_target_name);
        if (index >= 0 && memcmp(g_discovered_nodes[index].addr.addr, seek_result_data->addr.addr,
            sizeof(seek_result_data->addr.addr)) == 0) {
            SLE_Client_Connect_Selected_Node(index);
        }
    }
}

static void SLE_Client_Connect_State_Callback(uint16_t conn_id, const sle_addr_t *addr,
    sle_acb_state_t conn_state, sle_pair_state_t pair_state, sle_disc_reason_t disc_reason)
{
    errcode_t ret;

    printf("[JS Master] 连接状态变化 conn:%u state:%u pair:%u reason:%u\r\n",
        conn_id, conn_state, pair_state, disc_reason);
    SLE_Client_Log_Address("[JS Master] 对端地址:", addr);

    if (conn_state == SLE_ACB_STATE_CONNECTED) {
        g_conn_id = conn_id;
        g_target_connected = true;
        if (pair_state == SLE_PAIR_NONE) {
            ret = sle_pair_remote_device(addr);
            SLE_Client_Log_Result("sle_pair_remote_device", ret);
            return;
        }
        ret = SLE_Client_Request_Exchange_Info();
        SLE_Client_Log_Result("request_exchange_info_after_reconnect", ret);
        return;
    }

    if (conn_state == SLE_ACB_STATE_DISCONNECTED) {
        printf("[JS Master] 对端已断开，保留发现列表并等待前端目标重连\r\n");
        SLE_Client_Reset_Link_State();
        if (g_sle_enabled) {
            SLE_Client_Start_Scan_Internal();
        }
    }
}

static void SLE_Client_Auth_Complete_Callback(uint16_t conn_id, const sle_addr_t *addr, errcode_t status,
    const sle_auth_info_evt_t *evt)
{
    (void)conn_id;
    (void)evt;
    printf("[JS Master] 认证完成 status:0x%lx\r\n", (unsigned long)status);
    if (status == ERRCODE_SUCC) {
        return;
    }
    SLE_Client_Log_Result("sle_remove_paired_remote_device", sle_remove_paired_remote_device(addr));
    SLE_Client_Start_Scan_Internal();
}

static void SLE_Client_Pair_Complete_Callback(uint16_t conn_id, const sle_addr_t *addr, errcode_t status)
{
    (void)addr;
    printf("[JS Master] 配对完成 conn:%u status:0x%lx\r\n", conn_id, (unsigned long)status);
    if (status != ERRCODE_SUCC) {
        SLE_Client_Start_Scan_Internal();
        return;
    }
    (void)SLE_Client_Request_Exchange_Info();
}

static void SLE_Client_Rssi_Callback(uint16_t conn_id, int8_t rssi, errcode_t status)
{
    printf("[JS Master] RSSI回调 conn:%u rssi:%d status:0x%lx\r\n", conn_id, rssi, (unsigned long)status);
}

static void SLE_Client_Exchange_Info_Callback(uint8_t client_id, uint16_t conn_id, ssap_exchange_info_t *param,
    errcode_t status)
{
    if (param == NULL) {
        printf("[JS Master] MTU交换回调为空 status:0x%lx\r\n", (unsigned long)status);
        return;
    }
    printf("[JS Master] MTU交换完成 client:%u conn:%u mtu:%lu version:%u status:0x%lx\r\n",
        client_id, conn_id, (unsigned long)param->mtu_size, param->version, (unsigned long)status);
    if (status == ERRCODE_SUCC) {
        (void)SLE_Client_Start_Service_Discovery();
    }
}

static void SLE_Client_Find_Service_Callback(uint8_t client_id, uint16_t conn_id,
    ssapc_find_service_result_t *service, errcode_t status)
{
    (void)client_id;
    (void)conn_id;
    if (status != ERRCODE_SUCC || service == NULL) {
        return;
    }
    if (SLE_Uuid_Equals_U16(&service->uuid, JS_SLE_SERVICE_UUID)) {
        g_service_start_handle = service->start_hdl;
        g_service_end_handle = service->end_hdl;
        printf("[JS Master] 找到目标服务 handle:[0x%04X-0x%04X]\r\n", g_service_start_handle, g_service_end_handle);
    }
}

static void SLE_Client_Find_Property_Callback(uint8_t client_id, uint16_t conn_id,
    ssapc_find_property_result_t *property, errcode_t status)
{
    (void)client_id;
    (void)conn_id;
    if (status != ERRCODE_SUCC || property == NULL) {
        return;
    }
    if (SLE_Uuid_Equals_U16(&property->uuid, JS_SLE_PROPERTY_UUID)) {
        g_property_handle = property->handle;
        printf("[JS Master] 找到目标特征 handle:0x%04X operate:0x%lx\r\n",
            g_property_handle, (unsigned long)property->operate_indication);
    }
}

static void SLE_Client_Find_Structure_Complete_Callback(uint8_t client_id, uint16_t conn_id,
    ssapc_find_structure_result_t *structure_result, errcode_t status)
{
    (void)client_id;
    (void)conn_id;
    (void)structure_result;
    printf("[JS Master] 发现流程完成 state:%u status:0x%lx\r\n", g_discovery_state, (unsigned long)status);
    if (status != ERRCODE_SUCC) {
        return;
    }
    if (g_discovery_state == JS_DISCOVERY_SERVICE) {
        if (g_service_start_handle == 0 || g_service_end_handle == 0) {
            printf("[JS Master] 未找到目标服务\r\n");
            return;
        }
        (void)SLE_Client_Start_Property_Discovery();
        return;
    }
    if (g_discovery_state == JS_DISCOVERY_PROPERTY) {
        if (g_property_handle == 0) {
            printf("[JS Master] 未找到目标特征\r\n");
            return;
        }
        printf("[JS Master] 主设备已就绪，可进行双向收发\r\n");
        SLE_Client_Log_Result("sle_read_remote_device_rssi", sle_read_remote_device_rssi(g_conn_id));
        g_discovery_state = JS_DISCOVERY_IDLE;
    }
}

static void SLE_Client_Read_Callback(uint8_t client_id, uint16_t conn_id, ssapc_handle_value_t *read_data,
    errcode_t status)
{
    printf("[JS Master] 读回调 client:%u conn:%u handle:0x%04X len:%u status:0x%lx\r\n",
        client_id, conn_id, read_data != NULL ? read_data->handle : 0,
        read_data != NULL ? read_data->data_len : 0, (unsigned long)status);
}

static void SLE_Client_Write_Callback(uint8_t client_id, uint16_t conn_id, ssapc_write_result_t *write_result,
    errcode_t status)
{
    printf("[JS Master] 写确认 client:%u conn:%u handle:0x%04X status:0x%lx\r\n",
        client_id, conn_id, write_result != NULL ? write_result->handle : 0, (unsigned long)status);
}

static void SLE_Client_Notification_Callback(uint8_t client_id, uint16_t conn_id, ssapc_handle_value_t *data,
    errcode_t status)
{
    static uint32_t notify_count = 0;
    (void)client_id;
    (void)conn_id;
    if (status != ERRCODE_SUCC || data == NULL || data->data == NULL) {
        return;
    }
    notify_count++;
    if ((notify_count % 100) == 0) {
        printf("[JS Master] 已收到 %lu 个模型包, 最近 handle:0x%04X len:%u\r\n",
            (unsigned long)notify_count, data->handle, data->data_len);
    }
    if (g_notify_cb != NULL) {
        g_notify_cb(data->data, data->data_len);
    }
}

static void SLE_Client_Indication_Callback(uint8_t client_id, uint16_t conn_id, ssapc_handle_value_t *data,
    errcode_t status)
{
    (void)client_id;
    (void)conn_id;
    if (status != ERRCODE_SUCC || data == NULL || data->data == NULL) {
        return;
    }
    printf("[JS Master] 收到指示 handle:0x%04X len:%u payload:%.*s\r\n",
        data->handle, data->data_len, (int)data->data_len, (const char *)data->data);
}

void SLE_Client_Register_Notify_Callback(SLE_ClientNotifyCallback_t cb)
{
    g_notify_cb = cb;
}

void SLE_Client_Init(void)
{
    errcode_t ret;
    SLE_Client_Reset_Link_State();
    g_target_selected = false;
    g_target_name[0] = '\0';

    g_seek_cbks.sle_enable_cb = SLE_Client_Enable_Callback;
    g_seek_cbks.seek_enable_cb = SLE_Client_Seek_Enable_Callback;
    g_seek_cbks.seek_disable_cb = SLE_Client_Seek_Disable_Callback;
    g_seek_cbks.seek_result_cb = SLE_Client_Seek_Result_Callback;
    ret = sle_announce_seek_register_callbacks(&g_seek_cbks);
    SLE_Client_Log_Result("sle_announce_seek_register_callbacks", ret);

    g_conn_cbks.connect_state_changed_cb = SLE_Client_Connect_State_Callback;
    g_conn_cbks.auth_complete_cb = SLE_Client_Auth_Complete_Callback;
    g_conn_cbks.pair_complete_cb = SLE_Client_Pair_Complete_Callback;
    g_conn_cbks.read_rssi_cb = SLE_Client_Rssi_Callback;
    ret = sle_connection_register_callbacks(&g_conn_cbks);
    SLE_Client_Log_Result("sle_connection_register_callbacks", ret);

    g_ssapc_cbks.exchange_info_cb = SLE_Client_Exchange_Info_Callback;
    g_ssapc_cbks.find_structure_cb = SLE_Client_Find_Service_Callback;
    g_ssapc_cbks.ssapc_find_property_cbk = SLE_Client_Find_Property_Callback;
    g_ssapc_cbks.find_structure_cmp_cb = SLE_Client_Find_Structure_Complete_Callback;
    g_ssapc_cbks.read_cfm_cb = SLE_Client_Read_Callback;
    g_ssapc_cbks.write_cfm_cb = SLE_Client_Write_Callback;
    g_ssapc_cbks.notification_cb = SLE_Client_Notification_Callback;
    g_ssapc_cbks.indication_cb = SLE_Client_Indication_Callback;
    ret = ssapc_register_callbacks(&g_ssapc_cbks);
    SLE_Client_Log_Result("ssapc_register_callbacks", ret);

    ret = enable_sle();
    SLE_Client_Log_Result("enable_sle", ret);
}

void SLE_Client_Start(const char *target_name)
{
    (void)target_name;
    printf("[JS Master] 前端选择模式已启用：启动后只扫描上报，不自动连接\r\n");
    if (g_sle_enabled) {
        SLE_Client_Start_Scan_Internal();
    }
}

void SLE_Client_Select_Target(const char *target_name)
{
    size_t target_len;
    int index;

    if (target_name == NULL || target_name[0] == '\0') {
        printf("[JS Master] 前端选择目标为空，忽略\r\n");
        return;
    }

    target_len = strlen(target_name);
    if (target_len > SLE_NAME_MAX_LEN) {
        target_len = SLE_NAME_MAX_LEN;
    }
    (void)memcpy(g_target_name, target_name, target_len);
    g_target_name[target_len] = '\0';
    g_target_selected = true;
    g_target_found = false;

    printf("[JS Master] 收到前端选择目标:%s\r\n", g_target_name);

    if (g_target_connected) {
        SLE_Client_Log_Result("sle_disconnect_remote_device", sle_disconnect_remote_device(&g_target_addr));
        return;
    }

    index = SLE_Client_Find_Node_By_Name(g_target_name);
    if (index >= 0) {
        SLE_Client_Connect_Selected_Node(index);
        return;
    }

    printf("[JS Master] 目标尚未在扫描列表中，继续扫描等待:%s\r\n", g_target_name);
    if (g_sle_enabled) {
        (void)sle_stop_seek();
        SLE_Client_Start_Scan_Internal();
    }
}

int SLE_Client_Send_Command(uint8_t *payload, uint16_t len)
{
    errcode_t ret;
    ssapc_write_param_t param = {0};

    if (payload == NULL || len == 0 || !SLE_Client_Is_Ready()) {
        return -1;
    }

    param.handle = g_property_handle;
    param.type = SSAP_PROPERTY_TYPE_VALUE;
    param.data_len = len;
    param.data = payload;

    ret = ssapc_write_cmd(g_client_id, g_conn_id, &param);
    SLE_Client_Log_Result("ssapc_write_cmd", ret);
    return (ret == ERRCODE_SUCC) ? 0 : -1;
}

bool SLE_Client_Is_Ready(void)
{
    return g_target_selected && g_target_connected &&
        (g_conn_id != SLE_INVALID_CONN_ID) &&
        (g_client_id != SLE_INVALID_CLIENT_ID) &&
        (g_property_handle != 0);
}

uint8_t SLE_Client_Get_Discovered_Nodes(SLE_ClientDiscoveredNode_t *nodes, uint8_t max_nodes)
{
    uint8_t count = 0;

    if (nodes == NULL || max_nodes == 0) {
        return 0;
    }

    for (uint8_t index = 0; index < JS_DISCOVERED_NODE_MAX && count < max_nodes; index++) {
        if (!g_discovered_nodes[index].in_use) {
            continue;
        }
        nodes[count].in_use = true;
        nodes[count].rssi = g_discovered_nodes[index].rssi;
        nodes[count].has_service = g_discovered_nodes[index].has_service;
        nodes[count].is_selected = g_target_selected && (strcmp(g_discovered_nodes[index].name, g_target_name) == 0);
        nodes[count].is_connected = nodes[count].is_selected && g_target_connected;
        (void)snprintf(nodes[count].name, sizeof(nodes[count].name), "%s", g_discovered_nodes[index].name);
        count++;
    }

    return count;
}

void SLE_Client_Get_Target_State(char *target_name, uint8_t target_name_len, bool *is_connected)
{
    if (target_name != NULL && target_name_len > 0) {
        if (g_target_selected) {
            (void)snprintf(target_name, target_name_len, "%s", g_target_name);
        } else {
            target_name[0] = '\0';
        }
    }
    if (is_connected != NULL) {
        *is_connected = g_target_connected;
    }
}
