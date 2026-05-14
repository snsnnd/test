#ifndef ATLAS_BRIDGE_CONFIG_H
#define ATLAS_BRIDGE_CONFIG_H

#include "platform_core.h"
#include "pinctrl_porting.h"

/*
 * Bridge UART settings for WS63 MASTER -> Atlas 200I serial uplink.
 * 注意：Atlas 端 main.py 启动时也必须使用相同波特率，例如：
 * python3 main.py serve --serial-baudrate 921600
 */

#define BRIDGE_UART_BUS                 1
#define BRIDGE_UART_BAUDRATE            921600
#define BRIDGE_UART_TX_PIN              15
#define BRIDGE_UART_RX_PIN              16
#define BRIDGE_UART_TX_PIN_MODE         1
#define BRIDGE_UART_RX_PIN_MODE         1
#define BRIDGE_UART_RX_BUFFER_SIZE      512
#define BRIDGE_UART_WRITE_TIMEOUT_MS    100

#endif
