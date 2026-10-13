#include "helmet_ota.h"

#include <stdbool.h>
#include <string.h>

#include "esp_ota_ops.h"
#include "esp_log.h"
#include "mbedtls/sha256.h"

static const char *TAG = "OTA";

typedef struct {
    helmet_transfer_status_t status;
    esp_ota_handle_t handle;
    const esp_partition_t *partition;
    uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE];
    mbedtls_sha256_context sha256;
    bool sha256_started;
} ota_context_t;

static ota_context_t context;

//------------------------ PRIVATE FUNCTIONS ------------------------
static void helmet_ota_reset(void){
    if (context.sha256_started) {
        mbedtls_sha256_free(&context.sha256);
    }
    memset(&context, 0, sizeof(context));
    context.status.state = HELMET_TRANSFER_IDLE;
}

//------------------------- PUBLIC FUNCTIONS ------------------------
esp_err_t helmet_ota_init(void){
    helmet_ota_reset();
    return ESP_OK;
}

esp_err_t helmet_ota_confirm_running_image(void){
    const esp_partition_t *running = esp_ota_get_running_partition();
    esp_ota_img_states_t state;
    const esp_err_t result = esp_ota_get_state_partition(running, &state);
    if (result != ESP_OK || state != ESP_OTA_IMG_PENDING_VERIFY) return result;

    const esp_err_t confirmation = esp_ota_mark_app_valid_cancel_rollback();
    if (confirmation == ESP_OK) ESP_LOGI(TAG, "OTA image confirmed; rollback cancelled");
    return confirmation;
}

esp_err_t helmet_ota_begin(size_t image_size, const uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE]){
    if (context.status.state == HELMET_TRANSFER_RECEIVING || image_size == 0 ||
        expected_sha256 == NULL) {
        return ESP_ERR_INVALID_STATE;
    }

    helmet_ota_reset();
    context.partition = esp_ota_get_next_update_partition(NULL);
    if (context.partition == NULL) return ESP_ERR_NOT_FOUND;
    if (image_size > context.partition->size) return ESP_ERR_INVALID_SIZE;

    esp_err_t err = esp_ota_begin(context.partition, image_size, &context.handle);
    if (err != ESP_OK) return err;

    mbedtls_sha256_init(&context.sha256);
    if (mbedtls_sha256_starts(&context.sha256, 0) != 0) {
        esp_ota_abort(context.handle);
        helmet_ota_reset();
        return ESP_FAIL;
    }
    context.sha256_started = true;
    memcpy(context.expected_sha256, expected_sha256, sizeof(context.expected_sha256));
    context.status.state = HELMET_TRANSFER_RECEIVING;
    context.status.total_size = image_size;
    return ESP_OK;
}

esp_err_t helmet_ota_write(const uint8_t *data, size_t length){
    if (context.status.state != HELMET_TRANSFER_RECEIVING || data == NULL || length == 0 ||
        length > context.status.total_size - context.status.bytes_received) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_err_t err = esp_ota_write(context.handle, data, length);
    if (err != ESP_OK) return err;
    if (mbedtls_sha256_update(&context.sha256, data, length) != 0) return ESP_FAIL;
    context.status.bytes_received += length;
    return ESP_OK;
}

esp_err_t helmet_ota_finish(void){
    if (context.status.state != HELMET_TRANSFER_RECEIVING ||
        context.status.bytes_received != context.status.total_size) {
        return ESP_ERR_INVALID_STATE;
    }

    context.status.state = HELMET_TRANSFER_VERIFYING;
    uint8_t actual_sha256[HELMET_TRANSFER_SHA256_SIZE];
    if (mbedtls_sha256_finish(&context.sha256, actual_sha256) != 0 ||
        memcmp(actual_sha256, context.expected_sha256, sizeof(actual_sha256)) != 0) {
        esp_ota_abort(context.handle);
        context.status.state = HELMET_TRANSFER_FAILED;
        return ESP_ERR_INVALID_CRC;
    }

    esp_err_t err = esp_ota_end(context.handle);
    if (err == ESP_OK) err = esp_ota_set_boot_partition(context.partition);
    context.status.state = err == ESP_OK ? HELMET_TRANSFER_COMPLETED : HELMET_TRANSFER_FAILED;
    return err;
}

void helmet_ota_abort(void){
    if (context.status.state == HELMET_TRANSFER_RECEIVING ||
        context.status.state == HELMET_TRANSFER_VERIFYING) {
        esp_ota_abort(context.handle);
    }
    helmet_ota_reset();
}

helmet_transfer_status_t helmet_ota_get_status(void){
    return context.status;
}
