idf_component_register(
    SRCS "helmet_storage.c"
    INCLUDE_DIRS "include"
    REQUIRES mbedtls ota esp_partition
)
