# Smart Helmet

Firmware, sensor experiments, datasets, and machine-learning work for the
two-processor smart-helmet project.

## Current phase

Validate each sensor independently before integration. After sensor validation,
develop ESP32 BLE and OTA, camera support, STM32 sensor fusion, and the UART
protocol between processors.

## Layout

```text
docs/                       System, wiring, and experiment documentation
firmware/stm32-mcu/          STM32 firmware
firmware/esp32-mcu/          ESP-IDF ESP32 firmware project
references/                  Arduino sketches and hardware bring-up references
data/                        Local raw and processed datasets
ml/                          ML exploration and reproducible source code
tools/                       Host-side data collection utilities
```

The root `.gitignore` applies to the complete repository.
