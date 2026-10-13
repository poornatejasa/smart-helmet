#include "helmet_config.h"

#include "nvs.h"
#include "nvs_flash.h"

static const char *NVS_NAMESPACE = "helmet_cfg";
static const char *INTERVAL_KEY = "interval";
static const char *ALERTS_KEY = "alerts";

static const helmet_config_t default_config = {
    .telemetry_interval_ms = 1000,
    .alerts_enabled = true,
};

static helmet_config_t config;

//------------------------ PRIVATE FUNCTIONS ------------------------
static esp_err_t helmet_config_save(void){
    nvs_handle_t handle;
    esp_err_t err = nvs_open(NVS_NAMESPACE, NVS_READWRITE, &handle);
    if (err != ESP_OK) return err;

    err = nvs_set_u16(handle, INTERVAL_KEY, config.telemetry_interval_ms);
    if (err == ESP_OK) err = nvs_set_u8(handle, ALERTS_KEY, config.alerts_enabled ? 1U : 0U);
    if (err == ESP_OK) err = nvs_commit(handle);
    nvs_close(handle);
    return err;
}

//------------------------- PUBLIC FUNCTIONS ------------------------
esp_err_t helmet_config_init(void){
    esp_err_t err = nvs_flash_init();
    if (err == ESP_ERR_NVS_NO_FREE_PAGES || err == ESP_ERR_NVS_NEW_VERSION_FOUND) {
        ESP_ERROR_CHECK(nvs_flash_erase());
        err = nvs_flash_init();
    }
    if (err != ESP_OK) return err;

    config = default_config;
    nvs_handle_t handle;
    if (nvs_open(NVS_NAMESPACE, NVS_READONLY, &handle) != ESP_OK) return ESP_OK;

    uint16_t interval;
    uint8_t alerts;
    if (nvs_get_u16(handle, INTERVAL_KEY, &interval) == ESP_OK &&
        interval >= HELMET_CONFIG_MIN_TELEMETRY_INTERVAL_MS &&
        interval <= HELMET_CONFIG_MAX_TELEMETRY_INTERVAL_MS) {
        config.telemetry_interval_ms = interval;
    }
    if (nvs_get_u8(handle, ALERTS_KEY, &alerts) == ESP_OK) {
        config.alerts_enabled = alerts != 0;
    }
    nvs_close(handle);
    return ESP_OK;
}

helmet_config_t helmet_config_get(void){
    return config;
}

esp_err_t helmet_config_set_telemetry_interval(uint16_t interval_ms){
    if (interval_ms < HELMET_CONFIG_MIN_TELEMETRY_INTERVAL_MS ||
        interval_ms > HELMET_CONFIG_MAX_TELEMETRY_INTERVAL_MS) {
        return ESP_ERR_INVALID_ARG;
    }
    config.telemetry_interval_ms = interval_ms;
    return helmet_config_save();
}

esp_err_t helmet_config_set_alerts_enabled(bool enabled){
    config.alerts_enabled = enabled;
    return helmet_config_save();
}

esp_err_t helmet_config_reset(void){
    config = default_config;
    return helmet_config_save();
}
