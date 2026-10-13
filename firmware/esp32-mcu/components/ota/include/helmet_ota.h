#pragma once

#include <stddef.h>
#include <stdint.h>

#include "esp_err.h"

#define HELMET_TRANSFER_SHA256_SIZE 32U

typedef enum {
    HELMET_TRANSFER_IDLE = 0,
    HELMET_TRANSFER_RECEIVING,
    HELMET_TRANSFER_VERIFYING,
    HELMET_TRANSFER_COMPLETED,
    HELMET_TRANSFER_FAILED,
} helmet_transfer_state_t;

typedef struct {
    helmet_transfer_state_t state;
    uint32_t bytes_received;
    uint32_t total_size;
} helmet_transfer_status_t;

esp_err_t helmet_ota_init(void);
esp_err_t helmet_ota_confirm_running_image(void);
esp_err_t helmet_ota_begin(size_t image_size, const uint8_t expected_sha256[HELMET_TRANSFER_SHA256_SIZE]);
esp_err_t helmet_ota_write(const uint8_t *data, size_t length);
esp_err_t helmet_ota_finish(void);
void helmet_ota_abort(void);
helmet_transfer_status_t helmet_ota_get_status(void);
