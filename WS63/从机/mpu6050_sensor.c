#include "mpu6050_sensor.h"
#include "cmsis_os2.h"
#include "pinctrl.h"
#include "i2c.h"
#include "platform_core.h"

#define MPU6050_I2C_BUS              I2C_BUS_1
#define MPU6050_I2C_BAUDRATE         400000
#define MPU6050_I2C_HSCODE           0
#define MPU6050_I2C_SDA_PIN          GPIO_15
#define MPU6050_I2C_SCL_PIN          GPIO_16
#define MPU6050_I2C_PIN_MODE         PIN_MODE_2

#define MPU6050_ADDR_PRIMARY         0x68
#define MPU6050_ADDR_SECONDARY       0x69
#define MPU6050_REG_SMPLRT_DIV       0x19
#define MPU6050_REG_CONFIG           0x1A
#define MPU6050_REG_GYRO_CONFIG      0x1B
#define MPU6050_REG_ACCEL_CONFIG     0x1C
#define MPU6050_REG_ACCEL_XOUT_H     0x3B
#define MPU6050_REG_PWR_MGMT_1       0x6B
#define MPU6050_REG_WHO_AM_I         0x75

static uint8_t g_mpu6050_ready = 0;
static uint16_t g_mpu6050_addr = MPU6050_ADDR_PRIMARY;

static int16_t MPU6050_Combine_Int16(uint8_t high, uint8_t low)
{
    return (int16_t)(((uint16_t)high << 8) | low);
}

static errcode_t MPU6050_I2C_Read(uint16_t dev_addr, uint8_t reg, uint8_t *buffer, uint32_t len)
{
    i2c_data_t data = { 0 };

    data.send_buf = &reg;
    data.send_len = 1;
    data.receive_buf = buffer;
    data.receive_len = len;

    return uapi_i2c_master_writeread(MPU6050_I2C_BUS, dev_addr, &data);
}

static errcode_t MPU6050_I2C_Write(uint16_t dev_addr, uint8_t reg, uint8_t value)
{
    uint8_t tx_buffer[2] = { reg, value };
    i2c_data_t data = { 0 };

    data.send_buf = tx_buffer;
    data.send_len = sizeof(tx_buffer);

    return uapi_i2c_master_write(MPU6050_I2C_BUS, dev_addr, &data);
}

uint8_t MPU6050_Sensor_IsReady(void)
{
    return g_mpu6050_ready;
}

errcode_t MPU6050_Sensor_Init(void)
{
    errcode_t ret;
    uint8_t who_am_i = 0;

    uapi_pin_set_mode(MPU6050_I2C_SCL_PIN, MPU6050_I2C_PIN_MODE);
    uapi_pin_set_mode(MPU6050_I2C_SDA_PIN, MPU6050_I2C_PIN_MODE);

    ret = uapi_i2c_master_init(MPU6050_I2C_BUS, MPU6050_I2C_BAUDRATE, MPU6050_I2C_HSCODE);
    if (ret != ERRCODE_SUCC) {
        g_mpu6050_ready = 0;
        return ret;
    }

    ret = MPU6050_I2C_Read(MPU6050_ADDR_PRIMARY, MPU6050_REG_WHO_AM_I, &who_am_i, 1);
    if ((ret == ERRCODE_SUCC) && ((who_am_i == MPU6050_ADDR_PRIMARY) || (who_am_i == MPU6050_ADDR_SECONDARY))) {
        g_mpu6050_addr = MPU6050_ADDR_PRIMARY;
    } else {
        ret = MPU6050_I2C_Read(MPU6050_ADDR_SECONDARY, MPU6050_REG_WHO_AM_I, &who_am_i, 1);
        if ((ret != ERRCODE_SUCC) || ((who_am_i != MPU6050_ADDR_PRIMARY) && (who_am_i != MPU6050_ADDR_SECONDARY))) {
            g_mpu6050_ready = 0;
            return (ret == ERRCODE_SUCC) ? ERRCODE_FAIL : ret;
        }
        g_mpu6050_addr = MPU6050_ADDR_SECONDARY;
    }

    ret = MPU6050_I2C_Write(g_mpu6050_addr, MPU6050_REG_PWR_MGMT_1, 0x00);
    if (ret != ERRCODE_SUCC) {
        g_mpu6050_ready = 0;
        return ret;
    }
    osDelay(10);

    ret = MPU6050_I2C_Write(g_mpu6050_addr, MPU6050_REG_SMPLRT_DIV, 0x07);
    if (ret != ERRCODE_SUCC) {
        g_mpu6050_ready = 0;
        return ret;
    }

    ret = MPU6050_I2C_Write(g_mpu6050_addr, MPU6050_REG_CONFIG, 0x03);
    if (ret != ERRCODE_SUCC) {
        g_mpu6050_ready = 0;
        return ret;
    }

    ret = MPU6050_I2C_Write(g_mpu6050_addr, MPU6050_REG_GYRO_CONFIG, 0x00);
    if (ret != ERRCODE_SUCC) {
        g_mpu6050_ready = 0;
        return ret;
    }

    ret = MPU6050_I2C_Write(g_mpu6050_addr, MPU6050_REG_ACCEL_CONFIG, 0x00);
    g_mpu6050_ready = (ret == ERRCODE_SUCC) ? 1 : 0;
    return ret;
}

errcode_t MPU6050_Sensor_Read(MPU6050_Data_t *out_data)
{
    uint8_t raw_data[14] = { 0 };
    errcode_t ret;

    if (out_data == NULL) {
        return ERRCODE_INVALID_PARAM;
    }
    if (!g_mpu6050_ready) {
        return ERRCODE_FAIL;
    }

    ret = MPU6050_I2C_Read(g_mpu6050_addr, MPU6050_REG_ACCEL_XOUT_H, raw_data, sizeof(raw_data));
    if (ret != ERRCODE_SUCC) {
        return ret;
    }

    out_data->accel_x = MPU6050_Combine_Int16(raw_data[0], raw_data[1]);
    out_data->accel_y = MPU6050_Combine_Int16(raw_data[2], raw_data[3]);
    out_data->accel_z = MPU6050_Combine_Int16(raw_data[4], raw_data[5]);
    out_data->gyro_x = MPU6050_Combine_Int16(raw_data[8], raw_data[9]);
    out_data->gyro_y = MPU6050_Combine_Int16(raw_data[10], raw_data[11]);
    out_data->gyro_z = MPU6050_Combine_Int16(raw_data[12], raw_data[13]);
    return ERRCODE_SUCC;
}
