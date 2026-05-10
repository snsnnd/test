#ifndef ATLAS_BRIDGE_CONFIG_H
#define ATLAS_BRIDGE_CONFIG_H

#include "platform_core.h"
#include "pinctrl_porting.h"

/*
 * Bridge UART settings for WS63 MASTER -> Atlas 200I serial uplink.
 * Update these macros before building the JS_MASTER bridge image.
 */

#define BRIDGE_UART_BUS                 UART_BUS_2
#define BRIDGE_UART_BAUDRATE            115200
#define BRIDGE_UART_TX_PIN              GPIO_07
#define BRIDGE_UART_RX_PIN              GPIO_08
#define BRIDGE_UART_TX_PIN_MODE         PIN_MODE_2
#define BRIDGE_UART_RX_PIN_MODE         PIN_MODE_2
#define BRIDGE_UART_RX_BUFFER_SIZE      64
#define BRIDGE_UART_WRITE_TIMEOUT_MS    0

#endif
