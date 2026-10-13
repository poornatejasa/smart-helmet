#include "helmet_ble.h"
#include "helmet_ble_services.h"
#include "helmet_ble_uuid.h"

#include <stddef.h>
#include <string.h>

#include "helmet_config.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "os/os_mbuf.h"

static uint16_t telemetry_handle;
static uint16_t alert_handle;
static bool telemetry_notifications_enabled;
static bool alert_notifications_enabled;
static helmet_ble_telemetry_t latest_telemetry;
static helmet_ble_alert_t pending_alert;
static bool alert_pending;
static TickType_t last_telemetry_notification;

//------------------------ PRIVATE FUNCTIONS ------------------------
static int helmet_ble_telemetry_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                                           struct ble_gatt_access_ctxt *ctxt, void *arg){
    (void)conn_handle;
    (void)attr_handle;
    (void)arg;
    if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR) return BLE_ATT_ERR_UNLIKELY;

    const size_t length = offsetof(helmet_ble_telemetry_t, payload) +
                          latest_telemetry.payload_length;
    return os_mbuf_append(ctxt->om, &latest_telemetry, length) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static void helmet_ble_notify(uint16_t handle, const void *data, size_t length){
    const uint16_t conn_handle = helmet_ble_connection_handle();
    if (conn_handle == BLE_HS_CONN_HANDLE_NONE || !helmet_ble_link_encrypted(conn_handle)) return;
    struct os_mbuf *buffer = ble_hs_mbuf_from_flat(data, length);
    if (buffer != NULL) (void)ble_gatts_notify_custom(conn_handle, handle, buffer);
}

//----------------------- PUBLIC GATT SERVICE -----------------------
const struct ble_gatt_svc_def helmet_telemetry_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(HELMET_TELEMETRY_SERVICE_UUID),
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = BLE_UUID16_DECLARE(HELMET_TELEMETRY_CHARACTERISTIC_UUID),
                .access_cb = helmet_ble_telemetry_access_cb,
                .val_handle = &telemetry_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_READ_ENC |
                         BLE_GATT_CHR_F_NOTIFY,
            },
            {
                .uuid = BLE_UUID16_DECLARE(HELMET_ALERT_CHARACTERISTIC_UUID),
                .access_cb = helmet_ble_telemetry_access_cb,
                .val_handle = &alert_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY,
            },
            {0},
        },
    },
    {0},
};

//------------------------- PUBLIC FUNCTIONS ------------------------
void helmet_ble_telemetry_init(void){
    memset(&latest_telemetry, 0, sizeof(latest_telemetry));
    telemetry_notifications_enabled = false;
    alert_notifications_enabled = false;
    alert_pending = false;
    last_telemetry_notification = 0;
}

esp_err_t helmet_ble_publish_telemetry(const helmet_ble_telemetry_t *telemetry){
    if (telemetry == NULL || telemetry->payload_length > HELMET_BLE_TELEMETRY_MAX_PAYLOAD) {
        return ESP_ERR_INVALID_ARG;
    }
    latest_telemetry = *telemetry;
    return ESP_OK;
}

esp_err_t helmet_ble_publish_alert(const helmet_ble_alert_t *alert){
    if (alert == NULL || alert->payload_length > HELMET_BLE_ALERT_MAX_PAYLOAD) {
        return ESP_ERR_INVALID_ARG;
    }
    if (!helmet_config_get().alerts_enabled) return ESP_OK;
    pending_alert = *alert;
    alert_pending = true;
    return ESP_OK;
}

void helmet_ble_telemetry_update(void){
    const TickType_t now = xTaskGetTickCount();
    const helmet_config_t config = helmet_config_get();
    if (telemetry_notifications_enabled &&
        now - last_telemetry_notification >= pdMS_TO_TICKS(config.telemetry_interval_ms)) {
        const size_t length = offsetof(helmet_ble_telemetry_t, payload) +
                              latest_telemetry.payload_length;
        helmet_ble_notify(telemetry_handle, &latest_telemetry, length);
        last_telemetry_notification = now;
    }
    if (alert_pending && alert_notifications_enabled) {
        const size_t length = offsetof(helmet_ble_alert_t, payload) + pending_alert.payload_length;
        helmet_ble_notify(alert_handle, &pending_alert, length);
        alert_pending = false;
    }
}

void helmet_ble_telemetry_handle_subscribe(const struct ble_gap_event *event){
    if (!helmet_ble_link_encrypted(event->subscribe.conn_handle)) return;
    if (event->subscribe.attr_handle == telemetry_handle) {
        telemetry_notifications_enabled = event->subscribe.cur_notify;
    }
    if (event->subscribe.attr_handle == alert_handle) {
        alert_notifications_enabled = event->subscribe.cur_notify;
    }
}

void helmet_ble_telemetry_handle_disconnect(uint16_t conn_handle){
    (void)conn_handle;
    telemetry_notifications_enabled = false;
    alert_notifications_enabled = false;
}
