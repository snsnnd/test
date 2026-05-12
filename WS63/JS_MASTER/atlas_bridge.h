#ifndef ATLAS_BRIDGE_H
#define ATLAS_BRIDGE_H

#include <stdbool.h>
#include <stdint.h>

void Atlas_Bridge_Init(void);
bool Atlas_Bridge_Is_Ready(void);
bool Atlas_Bridge_Enqueue_Packet(const uint8_t *payload, uint16_t len);

#endif
