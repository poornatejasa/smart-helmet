#include "helmet_ble.h"
#include "helmet_config.h"
#include "helmet_led.h"
#include "helmet_ota.h"
#include "helmet_storage.h"

#include "esp_log.h"
#include "esp_ota_ops.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

static const char *TAG = "MAIN";

//-------------------------- SYSTEM INIT --------------------------
static void initialization(void){
    ESP_ERROR_CHECK(helmet_config_init());
    ESP_ERROR_CHECK(helmet_ota_init());
    ESP_ERROR_CHECK(helmet_storage_init());
    ESP_ERROR_CHECK(helmet_ble_init());
}

//--------------------------- MAIN TASK ----------------------------
void app_main(void){
    const esp_partition_t *running = esp_ota_get_running_partition();
    ESP_LOGI(TAG, "Running partition: %s", running->label);

    esp_err_t led_err = helmet_led_init();
    if (led_err != ESP_OK) {
        ESP_LOGW(TAG, "Status LED disabled: %s", esp_err_to_name(led_err));
    }
    initialization();
    ESP_ERROR_CHECK(helmet_ota_confirm_running_image());
    ESP_LOGI(TAG, "BLE services ready; awaiting UART and sensor integration");

    while (true){
        /* BLE callbacks only validate/copy input. Flash and NVS work happens here. */
        helmet_ble_update();
        helmet_led_set_connected(helmet_ble_connected());
        vTaskDelay(pdMS_TO_TICKS(10));
    }
}
