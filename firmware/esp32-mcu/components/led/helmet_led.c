#include "helmet_led.h"

#include "esp_log.h"
#include "led_strip.h"

#define HELMET_LED_GPIO 8
#define HELMET_LED_BRIGHTNESS 16

static const char *TAG = "HELMET_LED";
static led_strip_handle_t status_led;
static int last_connection_state = -1;

static void helmet_led_write(bool connected) {
    if (status_led == NULL || last_connection_state == (int)connected) return;

    /* led_strip_set_pixel() takes red, green, blue values. */
    esp_err_t err = led_strip_set_pixel(
        status_led,
        0,
        connected ? 0 : HELMET_LED_BRIGHTNESS,
        0,
        connected ? HELMET_LED_BRIGHTNESS : 0);
    if (err == ESP_OK) err = led_strip_refresh(status_led);
    if (err == ESP_OK) {
        last_connection_state = (int)connected;
    } else {
        ESP_LOGE(TAG, "Could not update status LED: %s", esp_err_to_name(err));
    }
}

esp_err_t helmet_led_init(void) {
    const led_strip_config_t strip_config = {
        .strip_gpio_num = HELMET_LED_GPIO,
        .max_leds = 1,
    };
    const led_strip_rmt_config_t rmt_config = {
        .resolution_hz = 10 * 1000 * 1000,
        .flags.with_dma = false,
    };

    esp_err_t err = led_strip_new_rmt_device(&strip_config, &rmt_config, &status_led);
    if (err != ESP_OK) {
        status_led = NULL;
        return err;
    }

    helmet_led_write(false);
    ESP_LOGI(TAG, "WS2812 status LED ready on GPIO%d", HELMET_LED_GPIO);
    return ESP_OK;
}

void helmet_led_set_connected(bool connected) {
    helmet_led_write(connected);
}
