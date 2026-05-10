if(CONFIG_ENABLE_JS_MASTER_APP)
    set(COMPONENT_NAME "js_master_app_static")

    set(SOURCES
        ${CMAKE_CURRENT_SOURCE_DIR}/main.c
        ${CMAKE_CURRENT_SOURCE_DIR}/sle_client_module.c
        ${CMAKE_CURRENT_SOURCE_DIR}/atlas_bridge.c
    )

    set(PUBLIC_HEADER
        ${CMAKE_CURRENT_SOURCE_DIR}
    )

    set(PRIVATE_HEADER
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/liteos_m/kal/cmsis
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/liteos_m/components/cmsis/2.0
        ${CMAKE_CURRENT_SOURCE_DIR}/../../protocol/sle/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../drivers/chips/ws63/inc
        ${CMAKE_CURRENT_SOURCE_DIR}/../../utils/native/lite/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/liteos/liteos_v208.5.0/Huawei_LiteOS/open_source/CMSIS/CMSIS/RTOS2/Include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../middleware/utils/app_init
        ${CMAKE_CURRENT_SOURCE_DIR}/../../middleware/utils/common_headers
        ${CMAKE_CURRENT_SOURCE_DIR}/../../middleware/utils/common_headers/native
        ${CMAKE_CURRENT_SOURCE_DIR}/../../include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../include/driver
        ${CMAKE_CURRENT_SOURCE_DIR}/../../include/middleware/services/bts/sle
        ${CMAKE_CURRENT_SOURCE_DIR}/../../include/middleware/services/wifi
        ${CMAKE_CURRENT_SOURCE_DIR}/../../open_source/libboundscheck/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../open_source/lwip/lwip_v2.1.3/src/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../open_source/lwip/lwip_v2.1.3/src/include/compat/posix
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/osal/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/osal/include/interrupt
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/osal/adapt/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../../kernel/osal_adapt/inc
    )

    set(PRIVATE_DEFINES
    )

    set(PUBLIC_DEFINES
    )

    set(COMPONENT_PUBLIC_CCFLAGS
    )

    set(COMPONENT_CCFLAGS
    )

    set(WHOLE_LINK
        true
    )

    set(MAIN_COMPONENT
        false
    )

    build_component()
endif()
