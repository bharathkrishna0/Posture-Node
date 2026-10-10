#include "inference.h"
#include "posture_model.h"

#include <zephyr/kernel.h>
#include <zephyr/logging/log.h>

LOG_MODULE_REGISTER(tflm, LOG_LEVEL_INF);

#include "tensorflow/lite/micro/micro_interpreter.h"
#include "tensorflow/lite/micro/micro_mutable_op_resolver.h"
#include "tensorflow/lite/micro/system_setup.h"
#include "tensorflow/lite/schema/schema_generated.h"

namespace {

constexpr int kTensorArenaSize = 80 * 1024;

/* Tensor arena lives in RAM */
alignas(16) static uint8_t tensor_arena[kTensorArenaSize];

const tflite::Model *model = nullptr;

tflite::MicroInterpreter *interpreter = nullptr;

} // namespace

int sg_model_init(void)
{
    LOG_INF("Initializing TensorFlow Lite Micro...");

    tflite::InitializeTarget();

    model = tflite::GetModel(g_posture_model);

    if (model->version() != TFLITE_SCHEMA_VERSION) {
        LOG_ERR("Model schema mismatch");
        return -1;
    }

    static tflite::MicroMutableOpResolver<10> resolver;

    resolver.AddConv2D();
    resolver.AddDepthwiseConv2D();
    resolver.AddFullyConnected();
    resolver.AddReshape();
    resolver.AddSoftmax();
    resolver.AddRelu();
    resolver.AddMean();
    resolver.AddMaxPool2D();
    resolver.AddConcatenation();
    resolver.AddQuantize();

    static tflite::MicroInterpreter static_interpreter(
        model,
        resolver,
        tensor_arena,
        kTensorArenaSize);

    interpreter = &static_interpreter;

    if (interpreter->AllocateTensors() != kTfLiteOk) {

        LOG_ERR("AllocateTensors failed");

        return -1;
    }

    LOG_INF("TensorFlow initialized");

    LOG_INF("Arena used: %d bytes",
            interpreter->arena_used_bytes());

    return 0;
}

int sg_run_inference(
    const float window[SG_WINDOW_SIZE][SG_RAW_FEATURES],
    float pitch_deg,
    float roll_deg,
    uint32_t bad_duration_s,
    sg_result_t *result)
{
    ARG_UNUSED(window);
    ARG_UNUSED(pitch_deg);
    ARG_UNUSED(roll_deg);
    ARG_UNUSED(bad_duration_s);
    ARG_UNUSED(result);

    return 0;
}
LOG_INF("TensorFlow Lite Micro initialized");
LOG_INF("Model size: %u bytes", g_posture_model_len);
LOG_INF("Arena used: %u bytes", interpreter->arena_used_bytes());