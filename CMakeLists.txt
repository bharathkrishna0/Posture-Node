
cmake_minimum_required(VERSION 3.20.0)

find_package(Zephyr REQUIRED HINTS $ENV{ZEPHYR_BASE})

project(BLET)
# ------------------------------------------------------
# TensorFlow Lite Micro
# ------------------------------------------------------
# Get the C++ stdlib path from the toolchain
execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=include
    OUTPUT_VARIABLE GCC_INCLUDE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)
target_include_directories(app PRIVATE

    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflite-micro
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflite-micro/tensorflow
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflm_tree
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflm_tree/third_party/flatbuffers/include
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflm_tree/third_party/gemmlowp
    # C++ stdlib headers for TFLite Micro
    ${GCC_INCLUDE_DIR}/c++/12.2.0
    ${GCC_INCLUDE_DIR}/c++/12.2.0/arm-zephyr-eabi

)
# Disable thread-safe local statics (recommended by Zephyr TFLM samples)
set(NO_THREADSAFE_STATICS
    $<TARGET_PROPERTY:compiler-cpp,no_threadsafe_statics>)

zephyr_compile_options(
    $<$<COMPILE_LANGUAGE:CXX>:${NO_THREADSAFE_STATICS}>
)

file(GLOB app_sources
    src/*
    src/ml/*
)

target_sources(app PRIVATE ${app_sources})


# Allow C++ stdlib for TFLite Micro only
set_source_files_properties(
    src/ml/inference.cpp
    PROPERTIES COMPILE_FLAGS "-undef"
)

# Find C++ stdlib path from toolchain
execute_process(
    COMMAND ${CMAKE_CXX_COMPILER} -print-file-name=include
    OUTPUT_VARIABLE GCC_INCLUDE_DIR
    OUTPUT_STRIP_TRAILING_WHITESPACE
)

string(REPLACE "/include" "" GCC_LIB_DIR ${GCC_INCLUDE_DIR})

target_include_directories(app PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflm_tree
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/tflm_tree/third_party/flatbuffers/include
    ${GCC_LIB_DIR}/include/c++/12.2.0
    ${GCC_LIB_DIR}/include/c++/12.2.0/arm-zephyr-eabi
)