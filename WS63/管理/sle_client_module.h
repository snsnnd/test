#ifndef SLE_CLIENT_MODULE_H
#define SLE_CLIENT_MODULE_H

#include <stdbool.h>
#include <stdint.h>

typedef void (*SLE_ClientNotifyCallback_t)(const uint8_t *data, uint16_t len);

#define SLE_CLIENT_DISCOVERED_NODE_MAX 8
#define SLE_CLIENT_NODE_NAME_MAX_LEN   31

typedef struct {
    bool in_use;
    int8_t rssi;
    bool has_service;
    bool is_selected;
    bool is_connected;
    char name[SLE_CLIENT_NODE_NAME_MAX_LEN + 1];
} SLE_ClientDiscoveredNode_t;

void SLE_Client_Init(void);
void SLE_Client_Start(const char *target_name);
void SLE_Client_Select_Target(const char *target_name);
int SLE_Client_Send_Command(uint8_t *payload, uint16_t len);
bool SLE_Client_Is_Ready(void);
void SLE_Client_Register_Notify_Callback(SLE_ClientNotifyCallback_t cb);
uint8_t SLE_Client_Get_Discovered_Nodes(SLE_ClientDiscoveredNode_t *nodes, uint8_t max_nodes);
void SLE_Client_Get_Target_State(char *target_name, uint8_t target_name_len, bool *is_connected);

#endif
