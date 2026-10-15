#include "helmet_storage.h"

#include <stdbool.h>
#include <string.h>

#include "esp_partition.h"
#include "mbedtls/sha256.h"

#define STORAGE_ERASE_SECTOR_SIZE 4096U

typedef struct {
    helmet_transfer_status_t status;
    const esp_partition_t *partition;
    uint8_t file_type;
    uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE];
    mbedtls_sha256_context sha256;
    bool sha256_started;
} storage_context_t;

static storage_context_t context;

//------------------------ PRIVATE FUNCTIONS ------------------------
static void helmet_storage_reset(void){
    if (context.sha256_started) {
        mbedtls_sha256_free(&context.sha256);
    }
    memset(&context, 0, sizeof(context));
    context.status.state = HELMET_TRANSFER_IDLE;
}

//------------------------- PUBLIC FUNCTIONS ------------------------
esp_err_t helmet_storage_init(void){
    helmet_storage_reset();
    context.partition = esp_partition_find_first(ESP_PARTITION_TYPE_DATA,
                                                 ESP_PARTITION_SUBTYPE_ANY,
                                                 "storage");
    return context.partition == NULL ? ESP_ERR_NOT_FOUND : ESP_OK;
}

esp_err_t helmet_storage_begin(uint8_t file_type, size_t file_size,
                               const uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE]){
    if (context.partition == NULL || file_size == 0 || expected_sha256 == NULL ||
        file_size > context.partition->size || context.status.state == HELMET_TRANSFER_RECEIVING) {
        return ESP_ERR_INVALID_ARG;
    }

    helmet_storage_reset();
    context.partition = esp_partition_find_first(ESP_PARTITION_TYPE_DATA,
                                                 ESP_PARTITION_SUBTYPE_ANY,
                                                 "storage");
    if (context.partition == NULL) return ESP_ERR_NOT_FOUND;

    const size_t erase_size = (file_size + STORAGE_ERASE_SECTOR_SIZE - 1U) &
                              ~(STORAGE_ERASE_SECTOR_SIZE - 1U);
    esp_err_t err = esp_partition_erase_range(context.partition, 0, erase_size);
    if (err != ESP_OK) return err;

    mbedtls_sha256_init(&context.sha256);
    if (mbedtls_sha256_starts(&context.sha256, 0) != 0) {
        helmet_storage_reset();
        return ESP_FAIL;
    }
    context.sha256_started = true;
    memcpy(context.expected_sha256, expected_sha256, sizeof(context.expected_sha256));
    context.file_type = file_type;
    context.status.state = HELMET_TRANSFER_RECEIVING;
    context.status.total_size = file_size;
    return ESP_OK;
}

esp_err_t helmet_storage_write(const uint8_t *data, size_t length){
    if (context.status.state != HELMET_TRANSFER_RECEIVING || data == NULL || length == 0 ||
        length > context.status.total_size - context.status.bytes_received) {
        return ESP_ERR_INVALID_ARG;
    }
    esp_err_t err = esp_partition_write(context.partition, context.status.bytes_received,
                                        data, length);
    if (err != ESP_OK) return err;
    if (mbedtls_sha256_update(&context.sha256, data, length) != 0) return ESP_FAIL;
    context.status.bytes_received += length;
    return ESP_OK;
}

esp_err_t helmet_storage_finish(void){
    if (context.status.state != HELMET_TRANSFER_RECEIVING ||
        context.status.bytes_received != context.status.total_size) {
        return ESP_ERR_INVALID_STATE;
    }

    context.status.state = HELMET_TRANSFER_VERIFYING;
    uint8_t actual_sha256[HELMET_TRANSFER_SHA256_SIZE];
    if (mbedtls_sha256_finish(&context.sha256, actual_sha256) != 0 ||
        memcmp(actual_sha256, context.expected_sha256, sizeof(actual_sha256)) != 0) {
        context.status.state = HELMET_TRANSFER_FAILED;
        return ESP_ERR_INVALID_CRC;
    }
    context.status.state = HELMET_TRANSFER_COMPLETED;
    return ESP_OK;
}

void helmet_storage_abort(void){
    helmet_storage_reset();
    context.partition = esp_partition_find_first(ESP_PARTITION_TYPE_DATA,
                                                 ESP_PARTITION_SUBTYPE_ANY,
                                                 "storage");
}

helmet_transfer_status_t helmet_storage_get_status(void){
    return context.status;
}

uint8_t helmet_storage_get_file_type(void){
    return context.file_type;
}
