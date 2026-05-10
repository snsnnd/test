#ifndef MPU6050_SENSOR_H
#define MPU6050_SENSOR_H

#include <stdint.h>
#include "errcode.h"

typedef struct {
    int16_t accel_x;
    int16_t accel_y;
    int16_t accel_z;
    int16_t gyro_x;
    int16_t gyro_y;
    int16_t gyro_z;
} MPU6050_Data_t;

errcode_t MPU6050_Sensor_Init(void);
errcode_t MPU6050_Sensor_Read(MPU6050_Data_t *out_data);
uint8_t MPU6050_Sensor_IsReady(void);

#endif // MPU6050_SENSOR_H
