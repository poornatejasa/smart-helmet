idf_component_register(
    SRCS "main.c"
    INCLUDE_DIRS "."
    REQUIRES ble config ota storage led
)
