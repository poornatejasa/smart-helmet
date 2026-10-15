#pragma once

#include <stdbool.h>

#include "esp_err.h"

/** Initialize the single WS2812 status LED on GPIO8. */
esp_err_t helmet_led_init(void);

/** Show blue for a connected BLE link and red otherwise. */
void helmet_led_set_connected(bool connected);
