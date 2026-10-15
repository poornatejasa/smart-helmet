#pragma once

#include "host/ble_gap.h"
#include "host/ble_gatt.h"

extern const struct ble_gatt_svc_def helmet_telemetry_gatt_svcs[];
extern const struct ble_gatt_svc_def helmet_config_gatt_svcs[];
extern const struct ble_gatt_svc_def helmet_ota_gatt_svcs[];
extern const struct ble_gatt_svc_def helmet_file_gatt_svcs[];

void helmet_ble_telemetry_init(void);
void helmet_ble_telemetry_update(void);
void helmet_ble_telemetry_handle_subscribe(const struct ble_gap_event *event);
void helmet_ble_telemetry_handle_disconnect(uint16_t conn_handle);

void helmet_ble_config_init(void);
void helmet_ble_config_update(void);
void helmet_ble_config_handle_subscribe(const struct ble_gap_event *event);
void helmet_ble_config_handle_disconnect(uint16_t conn_handle);

void helmet_ble_ota_init(void);
void helmet_ble_ota_update(void);
void helmet_ble_ota_handle_subscribe(const struct ble_gap_event *event);
void helmet_ble_ota_handle_disconnect(uint16_t conn_handle);

void helmet_ble_file_init(void);
void helmet_ble_file_update(void);
void helmet_ble_file_handle_subscribe(const struct ble_gap_event *event);
void helmet_ble_file_handle_disconnect(uint16_t conn_handle);
