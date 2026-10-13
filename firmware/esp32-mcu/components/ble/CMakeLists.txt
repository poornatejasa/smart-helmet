idf_component_register(
    SRCS
        "transport/helmet_ble_transport.c"
        "services/helmet_ble_telemetry.c"
        "services/helmet_ble_config.c"
        "services/helmet_ble_transfer.c"
    INCLUDE_DIRS "include"
    REQUIRES bt nvs_flash config ota storage
)
