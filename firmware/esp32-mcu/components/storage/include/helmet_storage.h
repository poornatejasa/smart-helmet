#pragma once

#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"
#include "helmet_ota.h"

esp_err_t helmet_storage_init(void);
esp_err_t helmet_storage_begin(uint8_t file_type, size_t file_size,
                               const uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE]);
esp_err_t helmet_storage_write(const uint8_t *data, size_t length);
esp_err_t helmet_storage_finish(void);
void helmet_storage_abort(void);
helmet_transfer_status_t helmet_storage_get_status(void);
uint8_t helmet_storage_get_file_type(void);
