#include "helmet_ble.h"
#include "helmet_ble_services.h"
#include "helmet_ble_uuid.h"

#include <string.h>

#include "helmet_config.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "host/ble_hs.h"
#include "os/os_mbuf.h"

#define CONFIG_COMMAND_SET_INTERVAL 0x01U
#define CONFIG_COMMAND_SET_ALERTS 0x02U
#define CONFIG_COMMAND_SET_NAME 0x03U
#define CONFIG_COMMAND_RESET 0x04U
#define CONFIG_RESULT_MARKER 0x80U
#define CONFIG_QUEUE_DEPTH 8U

typedef struct {
    uint8_t command;
    uint16_t interval_ms;
    bool alerts_enabled;
    uint8_t name_length;
    char name[HELMET_BLE_DEVICE_NAME_MAX_LENGTH];
} config_work_item_t;

static uint16_t config_handle;
static uint16_t result_handle;
static uint16_t result_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static bool result_notifications_enabled;
static QueueHandle_t config_queue;

//------------------------ PRIVATE FUNCTIONS ------------------------
static void helmet_ble_config_notify(uint8_t command, esp_err_t result){
    if (!result_notifications_enabled || !helmet_ble_link_encrypted(result_conn_handle)) return;
    const uint8_t payload[] = {CONFIG_RESULT_MARKER, command, result == ESP_OK ? 0U : 1U};
    struct os_mbuf *buffer = ble_hs_mbuf_from_flat(payload, sizeof(payload));
    if (buffer != NULL) (void)ble_gatts_notify_custom(result_conn_handle, result_handle, buffer);
}

static int helmet_ble_config_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                                       struct ble_gatt_access_ctxt *ctxt, void *arg){
    (void)attr_handle;
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
        const helmet_config_t config = helmet_config_get();
        const char *name = helmet_ble_get_device_name();
        const size_t name_length = strlen(name);
        uint8_t response[5 + HELMET_BLE_DEVICE_NAME_MAX_LENGTH] = {
            1U,
            (uint8_t)(config.telemetry_interval_ms & 0xFFU),
            (uint8_t)(config.telemetry_interval_ms >> 8U),
            config.alerts_enabled ? 1U : 0U,
            (uint8_t)name_length,
        };
        memcpy(&response[5], name, name_length);
        return os_mbuf_append(ctxt->om, response, 5 + name_length) == 0
                   ? 0
                   : BLE_ATT_ERR_INSUFFICIENT_RES;
    }
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR || config_queue == NULL) {
        return BLE_ATT_ERR_UNLIKELY;
    }

    const uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    uint8_t request[1 + HELMET_BLE_DEVICE_NAME_MAX_LENGTH];
    if (length < 1 || length > sizeof(request) ||
        os_mbuf_copydata(ctxt->om, 0, length, request) != 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    config_work_item_t item = {.command = request[0]};
    switch (item.command) {
        case CONFIG_COMMAND_SET_INTERVAL:
            if (length != 3) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            item.interval_ms = (uint16_t)request[1] | ((uint16_t)request[2] << 8U);
            break;
        case CONFIG_COMMAND_SET_ALERTS:
            if (length != 2 || request[1] > 1U) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            item.alerts_enabled = request[1] != 0;
            break;
        case CONFIG_COMMAND_SET_NAME:
            if (length < 2 || length - 1 > HELMET_BLE_DEVICE_NAME_MAX_LENGTH) {
                return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            }
            item.name_length = length - 1;
            memcpy(item.name, &request[1], item.name_length);
            break;
        case CONFIG_COMMAND_RESET:
            if (length != 1) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
            break;
        default:
            return BLE_ATT_ERR_UNLIKELY;
    }

    if (xQueueSend(config_queue, &item, 0) != pdTRUE) return BLE_ATT_ERR_INSUFFICIENT_RES;
    result_conn_handle = conn_handle;
    return 0;
}

//----------------------- PUBLIC GATT SERVICE -----------------------
const struct ble_gatt_svc_def helmet_config_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(HELMET_CONFIG_SERVICE_UUID),
        .characteristics = (struct ble_gatt_chr_def[]) {
            {
                .uuid = BLE_UUID16_DECLARE(HELMET_CONFIG_CHARACTERISTIC_UUID),
                .access_cb = helmet_ble_config_access_cb,
                .val_handle = &config_handle,
                .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE |
                         BLE_GATT_CHR_F_READ_ENC | BLE_GATT_CHR_F_WRITE_ENC,
            },
            {
                .uuid = BLE_UUID16_DECLARE(HELMET_CONFIG_RESULT_UUID),
                .access_cb = helmet_ble_config_access_cb,
                .val_handle = &result_handle,
                .flags = BLE_GATT_CHR_F_NOTIFY,
            },
            {0},
        },
    },
    {0},
};

//------------------------- PUBLIC FUNCTIONS ------------------------
void helmet_ble_config_init(void){
    config_queue = xQueueCreate(CONFIG_QUEUE_DEPTH, sizeof(config_work_item_t));
    result_notifications_enabled = false;
    result_conn_handle = BLE_HS_CONN_HANDLE_NONE;
}

void helmet_ble_config_update(void){
    config_work_item_t item;
    if (config_queue == NULL || xQueueReceive(config_queue, &item, 0) != pdTRUE) return;

    esp_err_t result = ESP_FAIL;
    switch (item.command) {
        case CONFIG_COMMAND_SET_INTERVAL:
            result = helmet_config_set_telemetry_interval(item.interval_ms);
            break;
        case CONFIG_COMMAND_SET_ALERTS:
            result = helmet_config_set_alerts_enabled(item.alerts_enabled);
            break;
        case CONFIG_COMMAND_SET_NAME:
            result = helmet_ble_set_device_name(item.name, item.name_length);
            break;
        case CONFIG_COMMAND_RESET:
            result = helmet_config_reset();
            if (result == ESP_OK) result = helmet_ble_reset_device_name();
            break;
        default:
            break;
    }
    helmet_ble_config_notify(item.command, result);
}

void helmet_ble_config_handle_subscribe(const struct ble_gap_event *event){
    if (event->subscribe.attr_handle == result_handle &&
        helmet_ble_link_encrypted(event->subscribe.conn_handle)) {
        result_notifications_enabled = event->subscribe.cur_notify;
        result_conn_handle = event->subscribe.conn_handle;
    }
}

void helmet_ble_config_handle_disconnect(uint16_t conn_handle){
    if (result_conn_handle == conn_handle) {
        result_conn_handle = BLE_HS_CONN_HANDLE_NONE;
        result_notifications_enabled = false;
    }
}
