#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#define HELMET_BLE_DEVICE_NAME_MAX_LENGTH 20U
#define HELMET_BLE_TELEMETRY_MAX_PAYLOAD 64U
#define HELMET_BLE_ALERT_MAX_PAYLOAD 32U

typedef struct __attribute__((packed)) {
    uint8_t version;
    uint8_t flags;
    uint16_t sequence;
    uint32_t timestamp_ms;
    uint8_t payload_length;
    uint8_t payload[HELMET_BLE_TELEMETRY_MAX_PAYLOAD];
} helmet_ble_telemetry_t;

typedef struct __attribute__((packed)) {
    uint8_t code;
    uint8_t severity;
    uint16_t sequence;
    uint32_t timestamp_ms;
    uint8_t payload_length;
    uint8_t payload[HELMET_BLE_ALERT_MAX_PAYLOAD];
} helmet_ble_alert_t;

esp_err_t helmet_ble_init(void);
void helmet_ble_update(void);
bool helmet_ble_connected(void);
bool helmet_ble_link_encrypted(uint16_t conn_handle);
uint16_t helmet_ble_connection_handle(void);
const char *helmet_ble_get_device_name(void);
esp_err_t helmet_ble_set_device_name(const char *name, size_t length);
esp_err_t helmet_ble_reset_device_name(void);
esp_err_t helmet_ble_publish_telemetry(const helmet_ble_telemetry_t *telemetry);
esp_err_t helmet_ble_publish_alert(const helmet_ble_alert_t *alert);
