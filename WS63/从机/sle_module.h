#ifndef SLE_MODULE_H
#define SLE_MODULE_H

#include <stdint.h>
#include <stdbool.h>

// 定义接收回调函数指针类型
typedef void (*SLE_ReceiveCallback_t)(uint8_t *data, uint16_t len);

// 星闪模块初始化
void SLE_Server_Init(void);

// 开始广播，并设置设备名称让主设备发现
void SLE_Start_Advertising(const char* device_name);

// 发送数据给主设备
int SLE_Send_Data(uint8_t *payload, uint16_t len);

// 查询当前是否已与主设备建立连接
bool SLE_IsConnected(void);

// 注册接收主设备数据的回调函数
void SLE_Register_Receive_Callback(SLE_ReceiveCallback_t cb);

#endif // SLE_MODULE_H
