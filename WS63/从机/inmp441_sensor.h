#ifndef INMP441_SENSOR_H
#define INMP441_SENSOR_H

#include <stdint.h>
#include "errcode.h"

#define INMP441_AUDIO_WINDOW_SAMPLES 32000U

typedef struct {
    uint32_t level;
} INMP441_Data_t;

errcode_t INMP441_Sensor_Init(void);
errcode_t INMP441_Sensor_Read(INMP441_Data_t *out_data);
errcode_t INMP441_Sensor_CopyLatestAudio(int16_t *out_audio, uint32_t max_samples, uint32_t *out_valid_samples);
uint8_t INMP441_Sensor_IsReady(void);

#endif // INMP441_SENSOR_H
