idf_component_register(
    SRCS "helmet_ota.c"
    INCLUDE_DIRS "include"
    REQUIRES app_update mbedtls
)
