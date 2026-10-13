#include "helmet_ble_services.h"
#include "helmet_ble_uuid.h"
#include "helmet_ble.h"

#include <string.h>

#include "helmet_ota.h"
#include "helmet_storage.h"
#include "esp_system.h"
#include "freertos/FreeRTOS.h"
#include "freertos/queue.h"
#include "freertos/task.h"
#include "host/ble_hs.h"
#include "os/os_mbuf.h"

#define TRANSFER_COMMAND_START 0x01U
#define TRANSFER_COMMAND_FINISH 0x02U
#define TRANSFER_COMMAND_ABORT 0x03U
#define TRANSFER_COMMAND_REBOOT 0x04U
#define TRANSFER_CHUNK_MAX_SIZE 240U
#define TRANSFER_QUEUE_DEPTH 8U

typedef struct {
    uint16_t length;
    uint8_t bytes[TRANSFER_CHUNK_MAX_SIZE];
} transfer_chunk_t;

typedef struct {
    uint8_t command;
    uint8_t file_type;
    uint32_t size;
    uint8_t sha256[HELMET_TRANSFER_SHA256_SIZE];
} transfer_command_t;

typedef struct __attribute__((packed)) {
    uint8_t state;
    uint8_t progress;
    uint32_t bytes_received;
    uint32_t total_size;
} transfer_status_packet_t;

static uint16_t ota_control_handle;
static uint16_t ota_data_handle;
static uint16_t ota_status_handle;
static uint16_t ota_owner = BLE_HS_CONN_HANDLE_NONE;
static bool ota_status_notifications;
static QueueHandle_t ota_data_queue;
static QueueHandle_t ota_command_queue;
static helmet_transfer_status_t ota_last_notified;

static uint16_t file_control_handle;
static uint16_t file_data_handle;
static uint16_t file_status_handle;
static uint16_t file_owner = BLE_HS_CONN_HANDLE_NONE;
static bool file_status_notifications;
static QueueHandle_t file_data_queue;
static QueueHandle_t file_command_queue;
static helmet_transfer_status_t file_last_notified;

//------------------------ PRIVATE FUNCTIONS ------------------------
static int transfer_copy(struct ble_gatt_access_ctxt *ctxt, void *destination, size_t length){
    if (OS_MBUF_PKTLEN(ctxt->om) != length ||
        os_mbuf_copydata(ctxt->om, 0, length, destination) != 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    return 0;
}

static uint8_t transfer_progress(const helmet_transfer_status_t *status){
    return status->total_size == 0 ? 0U :
           (uint8_t)((100U * status->bytes_received) / status->total_size);
}

static void transfer_notify(uint16_t conn_handle, uint16_t handle, bool enabled,
                            const helmet_transfer_status_t *status){
    if (!enabled || !helmet_ble_link_encrypted(conn_handle)) return;
    const transfer_status_packet_t packet = {
        .state = (uint8_t)status->state,
        .progress = transfer_progress(status),
        .bytes_received = status->bytes_received,
        .total_size = status->total_size,
    };
    struct os_mbuf *buffer = ble_hs_mbuf_from_flat(&packet, sizeof(packet));
    if (buffer != NULL) (void)ble_gatts_notify_custom(conn_handle, handle, buffer);
}

static bool transfer_status_changed(const helmet_transfer_status_t *left,
                                    const helmet_transfer_status_t *right){
    return left->state != right->state || left->bytes_received != right->bytes_received ||
           left->total_size != right->total_size;
}

static int ota_status_read(struct ble_gatt_access_ctxt *ctxt){
    const helmet_transfer_status_t status = helmet_ota_get_status();
    const transfer_status_packet_t packet = {
        .state = (uint8_t)status.state,
        .progress = transfer_progress(&status),
        .bytes_received = status.bytes_received,
        .total_size = status.total_size,
    };
    return os_mbuf_append(ctxt->om, &packet, sizeof(packet)) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int file_status_read(struct ble_gatt_access_ctxt *ctxt){
    const helmet_transfer_status_t status = helmet_storage_get_status();
    const transfer_status_packet_t packet = {
        .state = (uint8_t)status.state,
        .progress = transfer_progress(&status),
        .bytes_received = status.bytes_received,
        .total_size = status.total_size,
    };
    return os_mbuf_append(ctxt->om, &packet, sizeof(packet)) == 0
               ? 0
               : BLE_ATT_ERR_INSUFFICIENT_RES;
}

static int ota_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                         struct ble_gatt_access_ctxt *ctxt, void *arg){
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) return ota_status_read(ctxt);
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;

    const uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (attr_handle == ota_data_handle) {
        transfer_chunk_t chunk;
        if (ota_owner != conn_handle || length == 0 || length > sizeof(chunk.bytes) ||
            helmet_ota_get_status().state != HELMET_TRANSFER_RECEIVING ||
            os_mbuf_copydata(ctxt->om, 0, length, chunk.bytes) != 0) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        chunk.length = length;
        return xQueueSend(ota_data_queue, &chunk, 0) == pdTRUE ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    uint8_t command;
    if (length < 1 || os_mbuf_copydata(ctxt->om, 0, 1, &command) != 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    transfer_command_t work = {.command = command};
    if (command == TRANSFER_COMMAND_START) {
        uint8_t request[1 + 4 + HELMET_TRANSFER_SHA256_SIZE];
        if (transfer_copy(ctxt, request, sizeof(request)) != 0) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        work.size = (uint32_t)request[1] | ((uint32_t)request[2] << 8U) |
                    ((uint32_t)request[3] << 16U) | ((uint32_t)request[4] << 24U);
        memcpy(work.sha256, &request[5], sizeof(work.sha256));
    } else if ((command != TRANSFER_COMMAND_FINISH && command != TRANSFER_COMMAND_ABORT &&
                command != TRANSFER_COMMAND_REBOOT) || length != 1 || ota_owner != conn_handle) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (xQueueSend(ota_command_queue, &work, 0) != pdTRUE) return BLE_ATT_ERR_INSUFFICIENT_RES;
    if (command == TRANSFER_COMMAND_START) ota_owner = conn_handle;
    return 0;
}

static int file_access_cb(uint16_t conn_handle, uint16_t attr_handle,
                          struct ble_gatt_access_ctxt *ctxt, void *arg){
    (void)arg;
    if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) return file_status_read(ctxt);
    if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) return BLE_ATT_ERR_UNLIKELY;

    const uint16_t length = OS_MBUF_PKTLEN(ctxt->om);
    if (attr_handle == file_data_handle) {
        transfer_chunk_t chunk;
        if (file_owner != conn_handle || length == 0 || length > sizeof(chunk.bytes) ||
            helmet_storage_get_status().state != HELMET_TRANSFER_RECEIVING ||
            os_mbuf_copydata(ctxt->om, 0, length, chunk.bytes) != 0) {
            return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        }
        chunk.length = length;
        return xQueueSend(file_data_queue, &chunk, 0) == pdTRUE ? 0 : BLE_ATT_ERR_INSUFFICIENT_RES;
    }

    uint8_t command;
    if (length < 1 || os_mbuf_copydata(ctxt->om, 0, 1, &command) != 0) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    transfer_command_t work = {.command = command};
    if (command == TRANSFER_COMMAND_START) {
        uint8_t request[1 + 1 + 4 + HELMET_TRANSFER_SHA256_SIZE];
        if (transfer_copy(ctxt, request, sizeof(request)) != 0) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
        work.file_type = request[1];
        work.size = (uint32_t)request[2] | ((uint32_t)request[3] << 8U) |
                    ((uint32_t)request[4] << 16U) | ((uint32_t)request[5] << 24U);
        memcpy(work.sha256, &request[6], sizeof(work.sha256));
    } else if ((command != TRANSFER_COMMAND_FINISH && command != TRANSFER_COMMAND_ABORT) ||
               length != 1 || file_owner != conn_handle) {
        return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }
    if (xQueueSend(file_command_queue, &work, 0) != pdTRUE) return BLE_ATT_ERR_INSUFFICIENT_RES;
    if (command == TRANSFER_COMMAND_START) file_owner = conn_handle;
    return 0;
}

static void ota_restart_task(void *arg){
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(250));
    esp_restart();
}

//----------------------- PUBLIC GATT SERVICES ----------------------
const struct ble_gatt_svc_def helmet_ota_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(HELMET_OTA_SERVICE_UUID),
        .characteristics = (struct ble_gatt_chr_def[]) {
            {.uuid = BLE_UUID16_DECLARE(HELMET_OTA_CONTROL_UUID), .access_cb = ota_access_cb,
             .val_handle = &ota_control_handle, .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC},
            {.uuid = BLE_UUID16_DECLARE(HELMET_OTA_DATA_UUID), .access_cb = ota_access_cb,
             .val_handle = &ota_data_handle, .flags = BLE_GATT_CHR_F_WRITE_NO_RSP | BLE_GATT_CHR_F_WRITE_ENC},
            {.uuid = BLE_UUID16_DECLARE(HELMET_OTA_STATUS_UUID), .access_cb = ota_access_cb,
             .val_handle = &ota_status_handle, .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_READ_ENC | BLE_GATT_CHR_F_NOTIFY},
            {0},
        },
    }, {0},
};

const struct ble_gatt_svc_def helmet_file_gatt_svcs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = BLE_UUID16_DECLARE(HELMET_FILE_SERVICE_UUID),
        .characteristics = (struct ble_gatt_chr_def[]) {
            {.uuid = BLE_UUID16_DECLARE(HELMET_FILE_CONTROL_UUID), .access_cb = file_access_cb,
             .val_handle = &file_control_handle, .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_ENC},
            {.uuid = BLE_UUID16_DECLARE(HELMET_FILE_DATA_UUID), .access_cb = file_access_cb,
             .val_handle = &file_data_handle, .flags = BLE_GATT_CHR_F_WRITE_NO_RSP | BLE_GATT_CHR_F_WRITE_ENC},
            {.uuid = BLE_UUID16_DECLARE(HELMET_FILE_STATUS_UUID), .access_cb = file_access_cb,
             .val_handle = &file_status_handle, .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_READ_ENC | BLE_GATT_CHR_F_NOTIFY},
            {0},
        },
    }, {0},
};

//------------------------- PUBLIC FUNCTIONS ------------------------
void helmet_ble_ota_init(void){
    ota_data_queue = xQueueCreate(TRANSFER_QUEUE_DEPTH, sizeof(transfer_chunk_t));
    ota_command_queue = xQueueCreate(TRANSFER_QUEUE_DEPTH, sizeof(transfer_command_t));
    ota_owner = BLE_HS_CONN_HANDLE_NONE;
    ota_status_notifications = false;
    memset(&ota_last_notified, 0xFF, sizeof(ota_last_notified));
}

void helmet_ble_file_init(void){
    file_data_queue = xQueueCreate(TRANSFER_QUEUE_DEPTH, sizeof(transfer_chunk_t));
    file_command_queue = xQueueCreate(TRANSFER_QUEUE_DEPTH, sizeof(transfer_command_t));
    file_owner = BLE_HS_CONN_HANDLE_NONE;
    file_status_notifications = false;
    memset(&file_last_notified, 0xFF, sizeof(file_last_notified));
}

void helmet_ble_ota_update(void){
    transfer_chunk_t chunk;
    while (ota_data_queue != NULL && xQueueReceive(ota_data_queue, &chunk, 0) == pdTRUE) {
        if (helmet_ota_write(chunk.bytes, chunk.length) != ESP_OK) helmet_ota_abort();
    }
    transfer_command_t command;
    if (ota_command_queue != NULL && xQueueReceive(ota_command_queue, &command, 0) == pdTRUE) {
        esp_err_t result = ESP_ERR_INVALID_ARG;
        if (command.command == TRANSFER_COMMAND_START) result = helmet_ota_begin(command.size, command.sha256);
        if (command.command == TRANSFER_COMMAND_FINISH) result = helmet_ota_finish();
        if (command.command == TRANSFER_COMMAND_ABORT) { helmet_ota_abort(); result = ESP_OK; }
        if (command.command == TRANSFER_COMMAND_REBOOT &&
            helmet_ota_get_status().state == HELMET_TRANSFER_COMPLETED) {
            result = xTaskCreate(ota_restart_task, "ota_restart", 2048, NULL,
                                 tskIDLE_PRIORITY + 1, NULL) == pdPASS ? ESP_OK : ESP_FAIL;
        }
        (void)result;
    }
    const helmet_transfer_status_t status = helmet_ota_get_status();
    if (transfer_status_changed(&status, &ota_last_notified)) {
        transfer_notify(ota_owner, ota_status_handle, ota_status_notifications, &status);
        ota_last_notified = status;
    }
}

void helmet_ble_file_update(void){
    transfer_chunk_t chunk;
    while (file_data_queue != NULL && xQueueReceive(file_data_queue, &chunk, 0) == pdTRUE) {
        if (helmet_storage_write(chunk.bytes, chunk.length) != ESP_OK) helmet_storage_abort();
    }
    transfer_command_t command;
    if (file_command_queue != NULL && xQueueReceive(file_command_queue, &command, 0) == pdTRUE) {
        esp_err_t result = ESP_ERR_INVALID_ARG;
        if (command.command == TRANSFER_COMMAND_START) {
            result = helmet_storage_begin(command.file_type, command.size, command.sha256);
        }
        if (command.command == TRANSFER_COMMAND_FINISH) result = helmet_storage_finish();
        if (command.command == TRANSFER_COMMAND_ABORT) { helmet_storage_abort(); result = ESP_OK; }
        (void)result;
    }
    const helmet_transfer_status_t status = helmet_storage_get_status();
    if (transfer_status_changed(&status, &file_last_notified)) {
        transfer_notify(file_owner, file_status_handle, file_status_notifications, &status);
        file_last_notified = status;
    }
}

void helmet_ble_ota_handle_subscribe(const struct ble_gap_event *event){
    if (event->subscribe.attr_handle == ota_status_handle && helmet_ble_link_encrypted(event->subscribe.conn_handle)) {
        ota_status_notifications = event->subscribe.cur_notify;
    }
}

void helmet_ble_file_handle_subscribe(const struct ble_gap_event *event){
    if (event->subscribe.attr_handle == file_status_handle && helmet_ble_link_encrypted(event->subscribe.conn_handle)) {
        file_status_notifications = event->subscribe.cur_notify;
    }
}

void helmet_ble_ota_handle_disconnect(uint16_t conn_handle){
    if (ota_owner == conn_handle) helmet_ota_abort();
    ota_owner = BLE_HS_CONN_HANDLE_NONE;
    ota_status_notifications = false;
}

void helmet_ble_file_handle_disconnect(uint16_t conn_handle){
    if (file_owner == conn_handle) helmet_storage_abort();
    file_owner = BLE_HS_CONN_HANDLE_NONE;
    file_status_notifications = false;
}
