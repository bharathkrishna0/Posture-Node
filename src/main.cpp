/*
 * SpineGuard IMU + BLE NUS + Madgwick Filter
 * SPDX-License-Identifier: Apache-2.0
 */

#include <zephyr/kernel.h>
#include <zephyr/device.h>
#include <zephyr/devicetree.h>
#include <zephyr/drivers/i2c.h>
#include <zephyr/drivers/gpio.h>
#include <zephyr/drivers/regulator.h>
#include <zephyr/settings/settings.h>
#include <zephyr/bluetooth/bluetooth.h>
#include <zephyr/bluetooth/conn.h>
#include <zephyr/bluetooth/gatt.h>
#include <zephyr/bluetooth/uuid.h>
#include <bluetooth/services/nus.h>
#include <dk_buttons_and_leds.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "ml/inference.h"
/* ── I2C ──────────────────────────────────────────────────────── */
static const struct device *imu_bus;
#define IMU_ADDR              0x6A
#define IMU_WHO_AM_I_EXPECTED 0x6B

/* ── Registers ────────────────────────────────────────────────── */
#define REG_WHO_AM_I   0x0F
#define REG_CTRL1_XL   0x10
#define REG_CTRL2_G    0x11
#define REG_OUTX_L_XL  0x28
#define REG_OUTX_L_G   0x22

/* ── Sensitivity ──────────────────────────────────────────────── */
#define ACCEL_SENS  0.061f    /* mg/LSB @ ±2g      */
#define GYRO_SENS   0.00875f  /* dps/LSB @ ±250dps */
#define MG_TO_MS2   0.00981f  /* mg → m/s²         */
#define DEG_TO_RAD  0.017453f /* degrees → radians  */

/* ── Madgwick filter ──────────────────────────────────────────── */
/* Beta controls how aggressively the filter trusts accelerometer
   vs gyroscope. 0.1 = smooth but slow to correct drift.
   0.5 = faster correction but noisier. 0.1 is good for posture. */
#define MADGWICK_BETA     0.1f
#define SAMPLE_PERIOD_S   1.0f   /* 1 second — match k_sleep below */

/* Quaternion — represents orientation in 3D space */
static float q0 = 1.0f, q1 = 0.0f, q2 = 0.0f, q3 = 0.0f;

/**
 * madgwick_update() — fuse accel + gyro into quaternion
 *
 * gx,gy,gz — gyroscope in radians/sec
 * ax,ay,az — accelerometer in any unit (normalised internally)
 */
static void madgwick_update(float gx, float gy, float gz,
                             float ax, float ay, float az)
{
    float recipNorm;
    float s0, s1, s2, s3;
    float qDot1, qDot2, qDot3, qDot4;
    float _2q0, _2q1, _2q2, _2q3;
    float _4q0, _4q1, _4q2, _4q3;
    float _8q1, _8q2;
    float q0q0, q1q1, q2q2, q3q3;

    /* Rate of change of quaternion from gyroscope */
    qDot1 = 0.5f * (-q1 * gx - q2 * gy - q3 * gz);
    qDot2 = 0.5f * ( q0 * gx + q2 * gz - q3 * gy);
    qDot3 = 0.5f * ( q0 * gy - q1 * gz + q3 * gx);
    qDot4 = 0.5f * ( q0 * gz + q1 * gy - q2 * gx);

    /* Only use accelerometer if it gives a valid reading */
    if (!((ax == 0.0f) && (ay == 0.0f) && (az == 0.0f))) {

        /* Normalise accelerometer */
        recipNorm = 1.0f / sqrtf(ax*ax + ay*ay + az*az);
        ax *= recipNorm;
        ay *= recipNorm;
        az *= recipNorm;

        /* Auxiliary variables */
        _2q0 = 2.0f * q0; _2q1 = 2.0f * q1;
        _2q2 = 2.0f * q2; _2q3 = 2.0f * q3;
        _4q0 = 4.0f * q0; _4q1 = 4.0f * q1;
        _4q2 = 4.0f * q2; _4q3 = 4.0f * q3;
        _8q1 = 8.0f * q1; _8q2 = 8.0f * q2;
        q0q0 = q0*q0; q1q1 = q1*q1;
        q2q2 = q2*q2; q3q3 = q3*q3;

        /* Gradient descent algorithm corrective step */
        s0 = _4q0*q2q2 + _2q2*ax + _4q0*q1q1 - _2q1*ay;
        s1 = _4q1*q3q3 - _2q3*ax + 4.0f*q0q0*q1
             - _2q0*ay - _4q1 + _8q1*q1q1 + _8q1*q2q2 + _4q1*az;
        s2 = 4.0f*q0q0*q2 + _2q0*ax + _4q2*q3q3
             - _2q3*ay - _4q2 + _8q2*q1q1 + _8q2*q2q2 + _4q2*az;
        s3 = 4.0f*q1q1*q3 - _2q1*ax + 4.0f*q2q2*q3 - _2q2*ay;

        /* Normalise gradient */
        recipNorm = 1.0f / sqrtf(s0*s0 + s1*s1 + s2*s2 + s3*s3);
        s0 *= recipNorm; s1 *= recipNorm;
        s2 *= recipNorm; s3 *= recipNorm;

        /* Apply feedback */
        qDot1 -= MADGWICK_BETA * s0;
        qDot2 -= MADGWICK_BETA * s1;
        qDot3 -= MADGWICK_BETA * s2;
        qDot4 -= MADGWICK_BETA * s3;
    }

    /* Integrate to get quaternion */
    q0 += qDot1 * SAMPLE_PERIOD_S;
    q1 += qDot2 * SAMPLE_PERIOD_S;
    q2 += qDot3 * SAMPLE_PERIOD_S;
    q3 += qDot4 * SAMPLE_PERIOD_S;

    /* Normalise quaternion */
    recipNorm = 1.0f / sqrtf(q0*q0 + q1*q1 + q2*q2 + q3*q3);
    q0 *= recipNorm; q1 *= recipNorm;
    q2 *= recipNorm; q3 *= recipNorm;
}

/**
 * Get pitch (forward/backward tilt) from quaternion
 * Positive = leaning forward (slouch)
 */
static float get_pitch(void)
{
    return asinf(-2.0f * (q1*q3 - q0*q2)) * (180.0f / 3.14159f);
}

/**
 * Get roll (lateral tilt) from quaternion
 * Positive = leaning right
 */
static float get_roll(void)
{
    return atan2f(2.0f*(q0*q1 + q2*q3),
                  q0*q0 - q1*q1 - q2*q2 + q3*q3)
           * (180.0f / 3.14159f);
}

/* ── BLE ──────────────────────────────────────────────────────── */
#define DEVICE_NAME     CONFIG_BT_DEVICE_NAME
#define DEVICE_NAME_LEN (sizeof(DEVICE_NAME) - 1)
#define RUN_STATUS_LED  DK_LED1
#define CON_STATUS_LED  DK_LED2

static struct bt_conn *current_conn;
static struct k_work_delayable adv_start_work;

static const struct bt_data ad[] = {
    BT_DATA_BYTES(BT_DATA_FLAGS, (BT_LE_AD_GENERAL | BT_LE_AD_NO_BREDR)),
    BT_DATA(BT_DATA_NAME_COMPLETE, DEVICE_NAME, DEVICE_NAME_LEN),
};
static const struct bt_data sd[] = {
    BT_DATA_BYTES(BT_DATA_UUID128_ALL, BT_UUID_NUS_VAL),
};

/* ── IMU data struct ──────────────────────────────────────────── */
struct imu_data {
    int16_t ax, ay, az;
    int16_t gx, gy, gz;
};

/* ── IMU I2C helpers ──────────────────────────────────────────── */
static int imu_reg_write(uint8_t reg, uint8_t val)
{
    uint8_t tx[2] = {reg, val};
    return i2c_write(imu_bus, tx, 2, IMU_ADDR);
}

static int imu_reg_read(uint8_t reg, uint8_t *val)
{
    return i2c_reg_read_byte(imu_bus, IMU_ADDR, reg, val);
}

static int imu_burst_read(uint8_t reg, uint8_t *data, uint8_t len)
{
    return i2c_burst_read(imu_bus, IMU_ADDR, reg, data, len);
}

/* ── IMU init ─────────────────────────────────────────────────── */
static int imu_init(void)
{
    uint8_t who_am_i;
    int err;

    if (!device_is_ready(imu_bus)) {
        printk("# I2C bus not ready\n");
        return -ENODEV;
    }
    printk("# I2C bus ready: %s\n", imu_bus->name);

    err = imu_reg_read(REG_WHO_AM_I, &who_am_i);
    if (err) {
        printk("# WHO_AM_I read failed: %d\n", err);
        return err;
    }
    printk("# WHO_AM_I = 0x%02x (expected 0x%02x)\n",
           who_am_i, IMU_WHO_AM_I_EXPECTED);

    /* accel 104Hz ±2g */
    err = imu_reg_write(REG_CTRL1_XL, 0x40);
    if (err) return err;

    /* gyro 104Hz ±250dps */
    err = imu_reg_write(REG_CTRL2_G, 0x40);
    if (err) return err;

    printk("# IMU initialized OK\n");
    return 0;
}

/* ── IMU read ─────────────────────────────────────────────────── */
static int imu_read(struct imu_data *out)
{
    uint8_t buf[6];
    int err;

    err = imu_burst_read(REG_OUTX_L_XL, buf, 6);
    if (err) return err;
    out->ax = (int16_t)(buf[0] | ((uint16_t)buf[1] << 8));
    out->ay = (int16_t)(buf[2] | ((uint16_t)buf[3] << 8));
    out->az = (int16_t)(buf[4] | ((uint16_t)buf[5] << 8));

    err = imu_burst_read(REG_OUTX_L_G, buf, 6);
    if (err) return err;
    out->gx = (int16_t)(buf[0] | ((uint16_t)buf[1] << 8));
    out->gy = (int16_t)(buf[2] | ((uint16_t)buf[3] << 8));
    out->gz = (int16_t)(buf[4] | ((uint16_t)buf[5] << 8));

    return 0;
}

/* ── BLE advertising ──────────────────────────────────────────── */
static int start_ble_advertising(void)
{
    int err = bt_le_adv_start(BT_LE_ADV_CONN_FAST_1,
                              ad, ARRAY_SIZE(ad),
                              sd, ARRAY_SIZE(sd));
    if (err == -EALREADY) return 0;
    if (err) { printk("# BLE adv failed: %d\n", err); return err; }
    printk("# BLE advertising as '%s'\n", DEVICE_NAME);
    return 0;
    if (sg_model_init() == 0)
    {
        printk("TensorFlow OK\n");
    }
    else
    {
        printk("TensorFlow FAILED\n");
    }
}

static void adv_start_work_handler(struct k_work *work)
{
    if (start_ble_advertising()) {
        k_work_reschedule(&adv_start_work, K_MSEC(1000));
    }
}


/* ── BLE callbacks ────────────────────────────────────────────── */
static void connected(struct bt_conn *conn, uint8_t err)
{
    if (err) {
        k_work_reschedule(&adv_start_work, K_MSEC(500));
        return;
    }
    current_conn = bt_conn_ref(conn);
    dk_set_led_on(CON_STATUS_LED);
    printk("# BLE connected\n");
}

static void disconnected(struct bt_conn *conn, uint8_t reason)
{
    printk("# BLE disconnected reason=%u\n", reason);
    if (current_conn) {
        bt_conn_unref(current_conn);
        current_conn = NULL;
        dk_set_led_off(CON_STATUS_LED);
    }
    k_work_reschedule(&adv_start_work, K_MSEC(250));
}

BT_CONN_CB_DEFINE(conn_callbacks) = {
    .connected    = connected,
    .disconnected = disconnected,
};

static void bt_receive_cb(struct bt_conn *conn,
                          const uint8_t *const data, uint16_t len)
{
    printk("# RX %d bytes\n", len);
}

static struct bt_nus_cb nus_cb = { .received = bt_receive_cb };

/* ── Main ─────────────────────────────────────────────────────── */
int main(void)
{
    int err;
    int blink      = 0;
    int sample_cnt = 0;
    char msg[80];

    k_sleep(K_MSEC(1500));
    printk("\n\n# SpineGuard + Madgwick starting...\n");

    dk_leds_init();
    settings_subsys_init();

    err = bt_enable(NULL);
    if (err) { printk("# bt_enable failed %d\n", err); return 0; }
    printk("# BT enabled\n");

    settings_load();

    err = bt_nus_init(&nus_cb);
    if (err) { printk("# NUS init failed %d\n", err); return 0; }

    k_work_init_delayable(&adv_start_work, adv_start_work_handler);
    start_ble_advertising();

    /* Power on IMU */
    const struct device *gpio0_dev = DEVICE_DT_GET(DT_NODELABEL(gpio0));
    if (device_is_ready(gpio0_dev)) {
        gpio_pin_configure(gpio0_dev, 1, GPIO_OUTPUT_ACTIVE);
        gpio_pin_set(gpio0_dev, 1, 1);
        printk("# GPIO P0.01 HIGH — IMU power on\n");
    }

    const struct device *imu_pwr_dev =
        DEVICE_DT_GET_OR_NULL(DT_NODELABEL(pdm_imu_pwr));
    if (imu_pwr_dev && device_is_ready(imu_pwr_dev)) {
        regulator_enable(imu_pwr_dev);
        printk("# IMU regulator enabled\n");
    }

    k_sleep(K_MSEC(500));

    imu_bus = DEVICE_DT_GET(DT_NODELABEL(i2c30));

    err = imu_init();
    if (err) {
        printk("# IMU init failed %d\n", err);
        return 0;
    }

    printk("# Madgwick filter initialised (beta=%.2f)\n",
           (double)MADGWICK_BETA);
    printk("# Main loop starting — 1Hz sample rate\n");

    struct imu_data raw;

    while (1) {
        dk_set_led(RUN_STATUS_LED, (++blink) % 2);

        err = imu_read(&raw);
        if (err != 0) {
            printk("# IMU read err %d\n", err);
            k_sleep(K_MSEC(1000));
            continue;
        }

        /* Convert to physical units */
        float ax = raw.ax * ACCEL_SENS * MG_TO_MS2;
        float ay = raw.ay * ACCEL_SENS * MG_TO_MS2;
        float az = raw.az * ACCEL_SENS * MG_TO_MS2;

        /* Gyro in radians/sec for Madgwick */
        float gx = raw.gx * GYRO_SENS * DEG_TO_RAD;
        float gy = raw.gy * GYRO_SENS * DEG_TO_RAD;
        float gz = raw.gz * GYRO_SENS * DEG_TO_RAD;

        /* ── Run Madgwick filter ── */
        madgwick_update(gx, gy, gz, ax, ay, az);

        /* ── Extract angles from quaternion ── */
        float pitch = get_pitch();   /* forward tilt — main posture metric */
        float roll  = get_roll();    /* lateral lean */

        /* ── Posture score 0–100 ── */
        float score = 100.0f - fabsf(pitch) * 2.0f;
        if (score < 0.0f) score = 0.0f;

        /* ── Fatigue state ── */
        const char *fatigue;
        if (score >= 75)      fatigue = "Alert";
        else if (score >= 45) fatigue = "Fatiguing";
        else                  fatigue = "Fatigued";

        printk("[%d] Pitch:%.1f Roll:%.1f Score:%.0f [%s] "
               "q:%.3f,%.3f,%.3f,%.3f\n",
               ++sample_cnt,
               (double)pitch, (double)roll, (double)score,
               fatigue,
               (double)q0, (double)q1, (double)q2, (double)q3);

        /* ── Send over BLE NUS ── */
        if (current_conn) {
            int len = snprintf(msg, sizeof(msg),
                "P:%.1f,R:%.1f,S:%.0f,F:%s\n",
                (double)pitch, (double)roll,
                (double)score, fatigue);
            bt_nus_send(NULL, (uint8_t *)msg, len);
        }

        k_sleep(K_MSEC(1000));
    }

    return 0;
}