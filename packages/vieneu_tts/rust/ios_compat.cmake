# Compatibility shim for sentencepiece / external dependencies on iOS with Ninja generator
if(NOT COMMAND set_xcode_property)
    macro(set_xcode_property TARGET XCODE_PROPERTY XCODE_VALUE)
        set_property(TARGET ${TARGET} PROPERTY XCODE_ATTRIBUTE_${XCODE_PROPERTY} ${XCODE_VALUE})
    endmacro()
endif()
