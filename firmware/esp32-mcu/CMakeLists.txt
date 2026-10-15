# ESP-IDF requires these project declarations in this order.
cmake_minimum_required(VERSION 3.16)

# Keep the active configuration beside the firmware instead of at repository root.
set(SDKCONFIG "${CMAKE_CURRENT_LIST_DIR}/idf-env/sdkconfig")
set(SDKCONFIG_DEFAULTS "${CMAKE_CURRENT_LIST_DIR}/idf-env/sdkconfig.defaults")

include($ENV{IDF_PATH}/tools/cmake/project.cmake)
project(smart_helmet)
