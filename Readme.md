# Smart Helmet System using RTOS

An RTOS-based intelligent helmet safety system designed to improve rider safety through real-time monitoring and control.

---

## Features

- Alcohol Detection
- Drowsiness Detection
- Fall Detection
- Helmet Wear Detection
- Buzzer & Vibration Alerts
- RTOS-Based Task Scheduling

---

## Hardware Used

- STM32 / Arduino
- MQ-3 Alcohol Sensor
- Accelerometer Module
- IR Sensor
- Buzzer
- Vibration Motor
- LEDs

---

## Software Used

- Embedded C
- Arduino IDE / STM32CubeIDE
- Git & GitHub

---

## RTOS Tasks

| Task | Type |
|---|---|
| Input Task | Periodic |
| Display Task | Periodic |
| Control Task | Event Driven |

---

## Folder Structure

```text
smart-helmet/
│
├── firmware/
├── hardware/
├── docs/
├── images/
└── README.md