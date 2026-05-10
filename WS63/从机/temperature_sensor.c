#include "temperature_sensor.h"
#include <stddef.h>
#include <math.h>
#include "adc.h"
#include "adc_porting.h"
#include "gpio.h"
#include "pinctrl.h"
#include "platform_core.h"

/*
 * 4引脚 NTC 模块推荐接法：
 * 1. AO -> GPIO_07 / ADC_CHANNEL_0
 * 2. DO -> GPIO_08 普通输入
 * 3. VCC -> 3.3V
 * 4. GND -> GND
 *
 * 选择依据：
 * - WS63V100 硬件用户指南指出 ADC 仅可复用到 GPIO_07~GPIO_12。
 * - 当前 INMP441 已占用 GPIO_10~GPIO_12，且 GPIO_09 / GPIO_11 属上电硬件配置相关脚。
 * - 因此 NTC 优先使用剩余更干净的 GPIO_07 / GPIO_08 组合。
 */
#define NTC_ADC_CHANNEL                 ADC_CHANNEL_0
#define NTC_DO_PIN                      GPIO_08
#define NTC_DO_PIN_MODE                 PIN_MODE_0
#define NTC_ADC_AVERAGE_SAMPLES         8U
#define NTC_ADC_REFERENCE_MV            3600.0f
#define NTC_PULL_RESISTOR_OHM           10000.0f
#define NTC_NOMINAL_RESISTANCE_OHM      10000.0f
#define NTC_NOMINAL_TEMPERATURE_C       25.0f
#define NTC_BETA_COEFFICIENT            3950.0f
#define NTC_PULLUP_TO_VREF              1
#define NTC_MIN_VALID_VOLTAGE_MV        1.0f
#define NTC_MAX_VALID_VOLTAGE_MV        (NTC_ADC_REFERENCE_MV - 1.0f)

static uint8_t g_temperature_ready = 0;
static float g_last_temperature_c = 25.0f;

static float Temperature_NTC_VoltageToResistance(float voltage_mv)
{
#if NTC_PULLUP_TO_VREF
    return NTC_PULL_RESISTOR_OHM * voltage_mv / (NTC_ADC_REFERENCE_MV - voltage_mv);
#else
    return NTC_PULL_RESISTOR_OHM * (NTC_ADC_REFERENCE_MV - voltage_mv) / voltage_mv;
#endif
}

static float Temperature_NTC_ResistanceToCelsius(float resistance_ohm)
{
    const float nominal_kelvin = NTC_NOMINAL_TEMPERATURE_C + 273.15f;
    float inverse_kelvin;

    inverse_kelvin = (1.0f / nominal_kelvin) +
        (logf(resistance_ohm / NTC_NOMINAL_RESISTANCE_OHM) / NTC_BETA_COEFFICIENT);
    return (1.0f / inverse_kelvin) - 273.15f;
}

static errcode_t Temperature_NTC_ReadVoltage(float *out_voltage_mv)
{
    uint32_t voltage_sum_mv = 0;
    uint16_t sample_mv = 0;
    errcode_t ret;

    if (out_voltage_mv == NULL) {
        return ERRCODE_INVALID_PARAM;
    }

    for (uint32_t i = 0; i < NTC_ADC_AVERAGE_SAMPLES; i++) {
        ret = adc_port_read(NTC_ADC_CHANNEL, &sample_mv);
        if (ret != ERRCODE_SUCC) {
            return ret;
        }
        voltage_sum_mv += sample_mv;
    }

    *out_voltage_mv = (float)voltage_sum_mv / (float)NTC_ADC_AVERAGE_SAMPLES;
    return ERRCODE_SUCC;
}

uint8_t Temperature_Sensor_IsReady(void)
{
    return g_temperature_ready;
}

errcode_t Temperature_Sensor_Init(void)
{
    errcode_t ret;

    uapi_pin_init();
    uapi_gpio_init();
    (void)uapi_pin_set_mode(NTC_DO_PIN, NTC_DO_PIN_MODE);
    (void)uapi_pin_set_pull(NTC_DO_PIN, PIN_PULL_TYPE_DISABLE);
    (void)uapi_gpio_set_dir(NTC_DO_PIN, GPIO_DIRECTION_INPUT);

    (void)uapi_pin_set_mode(GPIO_07, PIN_MODE_0);
    ret = uapi_adc_init(ADC_CLOCK_500KHZ);

    g_temperature_ready = (ret == ERRCODE_SUCC) ? 1 : 0;
    return ret;
}

errcode_t Temperature_Sensor_Read(TemperatureSensor_Data_t *out_data)
{
    float voltage_mv;
    float resistance_ohm;
    errcode_t ret;

    if (out_data == NULL) {
        return ERRCODE_INVALID_PARAM;
    }

    out_data->digital_level = (uint8_t)uapi_gpio_get_val(NTC_DO_PIN);

    ret = Temperature_NTC_ReadVoltage(&voltage_mv);
    if (ret != ERRCODE_SUCC) {
        g_temperature_ready = 0;
        out_data->value = g_last_temperature_c;
        return ret;
    }

    if ((voltage_mv <= NTC_MIN_VALID_VOLTAGE_MV) || (voltage_mv >= NTC_MAX_VALID_VOLTAGE_MV)) {
        g_temperature_ready = 0;
        out_data->value = g_last_temperature_c;
        return ERRCODE_FAIL;
    }

    resistance_ohm = Temperature_NTC_VoltageToResistance(voltage_mv);
    g_last_temperature_c = Temperature_NTC_ResistanceToCelsius(resistance_ohm);

    g_temperature_ready = 1;
    out_data->value = g_last_temperature_c;
    return ERRCODE_SUCC;
}
