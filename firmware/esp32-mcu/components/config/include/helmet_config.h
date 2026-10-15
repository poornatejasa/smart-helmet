#pragma once

#include <stdbool.h>
#include <stdint.h>

#include "esp_err.h"

#define HELMET_CONFIG_MIN_TELEMETRY_INTERVAL_MS 100U
#define HELMET_CONFIG_MAX_TELEMETRY_INTERVAL_MS 60000U

typedef struct {
    uint16_t telemetry_interval_ms;
    bool alerts_enabled;
} helmet_config_t;

esp_err_t helmet_config_init(void);
helmet_config_t helmet_config_get(void);
esp_err_t helmet_config_set_telemetry_interval(uint16_t interval_ms);
esp_err_t helmet_config_set_alerts_enabled(bool enabled);
esp_err_t helmet_config_reset(void);
