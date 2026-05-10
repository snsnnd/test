#ifndef TEMPERATURE_SENSOR_H
#define TEMPERATURE_SENSOR_H

#include <stdint.h>
#include "errcode.h"

typedef struct {
    float value;
    uint8_t digital_level;
} TemperatureSensor_Data_t;

errcode_t Temperature_Sensor_Init(void);
errcode_t Temperature_Sensor_Read(TemperatureSensor_Data_t *out_data);
uint8_t Temperature_Sensor_IsReady(void);

#endif // TEMPERATURE_SENSOR_H
