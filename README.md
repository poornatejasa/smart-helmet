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
firmware/main-controller/   STM32/main-controller tests and application
firmware/esp32/              ESP32 tests and application
data/                        Local raw and processed datasets
ml/                          ML exploration and reproducible source code
tools/                       Host-side data collection utilities
```

The root `.gitignore` applies to the complete repository.
