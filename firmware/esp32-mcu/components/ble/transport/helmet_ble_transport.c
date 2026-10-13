#include "helmet_ble.h"
#include "helmet_ble_services.h"
#include "helmet_ble_uuid.h"

#include <string.h>

#include "esp_log.h"
#include "nvs.h"
#include "nvs_flash.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/util/util.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "store/config/ble_store_config.h"

/* ESP-IDF's NimBLE store component exports this initializer without a public header declaration. */
void ble_store_config_init(void);

static const char *TAG = "BLE_TRANSPORT";
static const char *DEFAULT_DEVICE_NAME = "Smart-Helmet";
static const char *NAME_NAMESPACE = "helmet_ble";
static const char *NAME_KEY = "device_name";

typedef struct {
    uint16_t conn_handle;
    bool encrypted;
} connection_t;

static connection_t connection;
static uint8_t own_addr_type;
static char device_name[HELMET_BLE_DEVICE_NAME_MAX_LENGTH + 1];

//------------------------ PRIVATE PROTOTYPES -----------------------
static void helmet_ble_start_advertising(void);
static int helmet_ble_gap_event(struct ble_gap_event *event, void *arg);
static esp_err_t helmet_ble_register_gatt_services(void);
static int helmet_ble_store_status_cb(struct ble_store_status_event *event, void *arg);
static connection_t *helmet_ble_find_connection(uint16_t conn_handle);
static bool helmet_ble_add_connection(uint16_t conn_handle);
static void helmet_ble_remove_connection(uint16_t conn_handle);

//------------------------ PRIVATE FUNCTIONS ------------------------
static void helmet_ble_host_task(void *param){
    (void)param;
    nimble_port_run();
    nimble_port_freertos_deinit();
}

static void helmet_ble_on_reset(int reason){
    ESP_LOGE(TAG, "NimBLE reset: %d", reason);
}

static int helmet_ble_store_status_cb(struct ble_store_status_event *event, void *arg){
    if (event->event_code == BLE_STORE_EVENT_FULL) {
        ESP_LOGW(TAG, "Bond store full: object=%d conn=%u",
                 event->full.obj_type, event->full.conn_handle);
    } else if (event->event_code == BLE_STORE_EVENT_OVERFLOW) {
        ESP_LOGW(TAG, "Bond store overflow: object=%d", event->overflow.obj_type);
    }

    return ble_store_util_status_rr(event, arg);
}

static void helmet_ble_load_device_name(void){
    strncpy(device_name, DEFAULT_DEVICE_NAME, sizeof(device_name));
    device_name[sizeof(device_name) - 1] = '\0';

    nvs_handle_t handle;
    size_t length = sizeof(device_name);
    if (nvs_open(NAME_NAMESPACE, NVS_READONLY, &handle) == ESP_OK) {
        if (nvs_get_str(handle, NAME_KEY, device_name, &length) != ESP_OK ||
            length <= 1 || length > sizeof(device_name)) {
            strncpy(device_name, DEFAULT_DEVICE_NAME, sizeof(device_name));
            device_name[sizeof(device_name) - 1] = '\0';
        }
        nvs_close(handle);
    }
}

static bool helmet_ble_device_name_is_valid(const char *name, size_t length){
    if (name == NULL || length == 0 || length > HELMET_BLE_DEVICE_NAME_MAX_LENGTH) return false;
    bool has_visible_character = false;
    for (size_t index = 0; index < length; index++) {
        const unsigned char character = (unsigned char)name[index];
        if (character < 0x20U || character > 0x7EU) return false;
        has_visible_character |= character != ' ';
    }
    return has_visible_character;
}

static void helmet_ble_on_sync(void){
    int rc = ble_hs_util_ensure_addr(0);
    if (rc != 0) {
        ESP_LOGE(TAG, "Could not ensure a BLE address (%d)", rc);
        return;
    }
    rc = ble_hs_id_infer_auto(0, &own_addr_type);
    if (rc != 0) {
        ESP_LOGE(TAG, "Could not infer BLE address type (%d)", rc);
        return;
    }
    ESP_LOGI(TAG, "BLE stack synchronized; own address type=%u", own_addr_type);
    ble_svc_gap_device_name_set(device_name);
    helmet_ble_start_advertising();
}

static connection_t *helmet_ble_find_connection(uint16_t conn_handle){
    return connection.conn_handle == conn_handle ? &connection : NULL;
}

static bool helmet_ble_add_connection(uint16_t conn_handle){
    if (connection.conn_handle != BLE_HS_CONN_HANDLE_NONE) return false;
    connection.conn_handle = conn_handle;
    connection.encrypted = false;
    return true;
}

static void helmet_ble_remove_connection(uint16_t conn_handle){
    connection_t *active_connection = helmet_ble_find_connection(conn_handle);
    if (active_connection != NULL) {
        active_connection->conn_handle = BLE_HS_CONN_HANDLE_NONE;
        active_connection->encrypted = false;
    }
}

static void helmet_ble_start_advertising(void){
    if (helmet_ble_connected()) {
        ESP_LOGI(TAG, "Advertising paused while connected");
        return;
    }
    if (ble_gap_adv_active()) {
        ESP_LOGI(TAG, "Advertising already active");
        return;
    }

    static const ble_uuid16_t advertised_services[] = {
        BLE_UUID16_INIT(HELMET_TELEMETRY_SERVICE_UUID),
        BLE_UUID16_INIT(HELMET_OTA_SERVICE_UUID),
    };
    struct ble_hs_adv_fields fields = {0};
    fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
    fields.uuids16 = advertised_services;
    fields.num_uuids16 = sizeof(advertised_services) / sizeof(advertised_services[0]);
    fields.uuids16_is_complete = 1;
    int rc = ble_gap_adv_set_fields(&fields);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to set advertising fields (%d)", rc);
        return;
    }

    struct ble_hs_adv_fields scan_response = {0};
    scan_response.name = (uint8_t *)device_name;
    scan_response.name_len = strlen(device_name);
    scan_response.name_is_complete = 1;
    rc = ble_gap_adv_rsp_set_fields(&scan_response);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to set scan-response fields (%d)", rc);
        return;
    }

    struct ble_gap_adv_params parameters = {0};
    parameters.conn_mode = BLE_GAP_CONN_MODE_UND;
    parameters.disc_mode = BLE_GAP_DISC_MODE_GEN;
    rc = ble_gap_adv_start(own_addr_type, NULL, BLE_HS_FOREVER,
                           &parameters, helmet_ble_gap_event, NULL);
    ESP_LOGI(TAG, "ble_gap_adv_start() = %d", rc);
    if (rc != 0) {
        ESP_LOGE(TAG, "Failed to start advertising (%d)", rc);
    } else {
        ESP_LOGI(TAG, "Advertising started as %s", device_name);
    }
}

static int helmet_ble_gap_event(struct ble_gap_event *event, void *arg){
    (void)arg;
    switch (event->type) {
        case BLE_GAP_EVENT_CONNECT:
            if (event->connect.status == 0 && helmet_ble_add_connection(event->connect.conn_handle)) {
                ESP_LOGI(TAG, "Connected: %u", event->connect.conn_handle);
            } else if (event->connect.status == 0) {
                ESP_LOGW(TAG, "Connection limit reached; terminating %u", event->connect.conn_handle);
                (void)ble_gap_terminate(event->connect.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            } else {
                ESP_LOGW(TAG, "Connection attempt failed (%d)", event->connect.status);
                helmet_ble_start_advertising();
            }
            break;

        case BLE_GAP_EVENT_ENC_CHANGE: {
            struct ble_gap_conn_desc description;
            const int rc = ble_gap_conn_find(event->enc_change.conn_handle, &description);
            connection_t *active_connection =
                helmet_ble_find_connection(event->enc_change.conn_handle);
            const bool encrypted = event->enc_change.status == 0 && rc == 0 &&
                                   description.sec_state.encrypted;
            if (active_connection != NULL) active_connection->encrypted = encrypted;
            if (!encrypted) {
                ESP_LOGE(TAG, "Pairing/encryption failed (status=%d, desc=%d)",
                         event->enc_change.status, rc);
                (void)ble_gap_terminate(event->enc_change.conn_handle, BLE_ERR_REM_USER_CONN_TERM);
            } else {
                ESP_LOGI(TAG, "Encrypted=%d Bonded=%d Authenticated=%d",
                         description.sec_state.encrypted, description.sec_state.bonded,
                         description.sec_state.authenticated);
            }
            break;
        }

        case BLE_GAP_EVENT_PARING_COMPLETE:
            ESP_LOGI(TAG, "Pairing complete: status=%d conn=%u",
                     event->pairing_complete.status, event->pairing_complete.conn_handle);
            if (event->pairing_complete.status != 0) {
                (void)ble_gap_terminate(event->pairing_complete.conn_handle,
                                        BLE_ERR_REM_USER_CONN_TERM);
            }
            break;

        case BLE_GAP_EVENT_SUBSCRIBE:
            helmet_ble_telemetry_handle_subscribe(event);
            helmet_ble_config_handle_subscribe(event);
            helmet_ble_ota_handle_subscribe(event);
            helmet_ble_file_handle_subscribe(event);
            break;

        case BLE_GAP_EVENT_DISCONNECT:
            helmet_ble_telemetry_handle_disconnect(event->disconnect.conn.conn_handle);
            helmet_ble_config_handle_disconnect(event->disconnect.conn.conn_handle);
            helmet_ble_ota_handle_disconnect(event->disconnect.conn.conn_handle);
            helmet_ble_file_handle_disconnect(event->disconnect.conn.conn_handle);
            helmet_ble_remove_connection(event->disconnect.conn.conn_handle);
            ESP_LOGI(TAG, "Disconnected (reason=%d)", event->disconnect.reason);
            helmet_ble_start_advertising();
            break;

        case BLE_GAP_EVENT_REPEAT_PAIRING: {
            struct ble_gap_conn_desc description;
            const int rc = ble_gap_conn_find(event->repeat_pairing.conn_handle, &description);
            if (rc == 0) {
                ESP_LOGW(TAG, "Replacing stale bond for repeat pairing");
                (void)ble_store_util_delete_peer(&description.peer_id_addr);
                return BLE_GAP_REPEAT_PAIRING_RETRY;
            }
            ESP_LOGE(TAG, "Repeat pairing lookup failed (%d)", rc);
            return BLE_GAP_REPEAT_PAIRING_IGNORE;
        }

        default:
            break;
    }
    return 0;
}

static esp_err_t helmet_ble_register_gatt_services(void){
    const struct ble_gatt_svc_def *services[] = {
        helmet_telemetry_gatt_svcs,
        helmet_config_gatt_svcs,
        helmet_ota_gatt_svcs,
        helmet_file_gatt_svcs,
    };
    const char *names[] = {"telemetry", "configuration", "OTA", "file"};

    for (size_t index = 0; index < sizeof(services) / sizeof(services[0]); index++) {
        const int count_result = ble_gatts_count_cfg(services[index]);
        if (count_result != 0) {
            ESP_LOGE(TAG, "Invalid %s GATT definition (%d)", names[index], count_result);
            return ESP_FAIL;
        }
    }
    for (size_t index = 0; index < sizeof(services) / sizeof(services[0]); index++) {
        const int add_result = ble_gatts_add_svcs(services[index]);
        if (add_result != 0) {
            ESP_LOGE(TAG, "Could not add %s GATT service (%d)", names[index], add_result);
            return ESP_FAIL;
        }
    }
    return ESP_OK;
}

//------------------------- PUBLIC FUNCTIONS ------------------------
esp_err_t helmet_ble_init(void){
    connection.conn_handle = BLE_HS_CONN_HANDLE_NONE;
    connection.encrypted = false;
    helmet_ble_load_device_name();

    ESP_ERROR_CHECK(nimble_port_init());
    ble_svc_gap_init();
    ble_svc_gatt_init();
    ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT;
    ble_hs_cfg.sm_bonding = 1;
    ble_hs_cfg.sm_mitm = 0;
    ble_hs_cfg.sm_sc = 0;
    ble_hs_cfg.sm_our_key_dist |= BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.sm_their_key_dist |= BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
    ble_hs_cfg.store_status_cb = helmet_ble_store_status_cb;
    ble_store_config_init();

    helmet_ble_telemetry_init();
    helmet_ble_config_init();
    helmet_ble_ota_init();
    helmet_ble_file_init();

    const esp_err_t gatt_result = helmet_ble_register_gatt_services();
    if (gatt_result != ESP_OK) return gatt_result;

    ble_hs_cfg.reset_cb = helmet_ble_on_reset;
    ble_hs_cfg.sync_cb = helmet_ble_on_sync;
    nimble_port_freertos_init(helmet_ble_host_task);
    return ESP_OK;
}

void helmet_ble_update(void){
    helmet_ble_config_update();
    helmet_ble_ota_update();
    helmet_ble_file_update();
    helmet_ble_telemetry_update();
}

bool helmet_ble_connected(void){ return connection.conn_handle != BLE_HS_CONN_HANDLE_NONE; }
bool helmet_ble_link_encrypted(uint16_t conn_handle){
    return connection.conn_handle == conn_handle && connection.encrypted;
}
uint16_t helmet_ble_connection_handle(void){ return connection.conn_handle; }
const char *helmet_ble_get_device_name(void){ return device_name; }

esp_err_t helmet_ble_set_device_name(const char *name, size_t length){
    if (!helmet_ble_device_name_is_valid(name, length)) return ESP_ERR_INVALID_ARG;
    memcpy(device_name, name, length);
    device_name[length] = '\0';
    ble_svc_gap_device_name_set(device_name);
    nvs_handle_t handle;
    esp_err_t result = nvs_open(NAME_NAMESPACE, NVS_READWRITE, &handle);
    if (result != ESP_OK) return result;
    result = nvs_set_str(handle, NAME_KEY, device_name);
    if (result == ESP_OK) result = nvs_commit(handle);
    nvs_close(handle);
    return result;
}

esp_err_t helmet_ble_reset_device_name(void){
    nvs_handle_t handle;
    esp_err_t result = nvs_open(NAME_NAMESPACE, NVS_READWRITE, &handle);
    if (result != ESP_OK) return result;
    result = nvs_erase_key(handle, NAME_KEY);
    if (result == ESP_ERR_NVS_NOT_FOUND) result = ESP_OK;
    if (result == ESP_OK) result = nvs_commit(handle);
    nvs_close(handle);
    if (result == ESP_OK) {
        strncpy(device_name, DEFAULT_DEVICE_NAME, sizeof(device_name));
        device_name[sizeof(device_name) - 1] = '\0';
        ble_svc_gap_device_name_set(device_name);
    }
    return result;
}
