/*
 * SpineGuard TinyML Inference Engine
 *
 * Public interface for TensorFlow Lite Micro inference.
 */

#ifndef SG_INFERENCE_H
#define SG_INFERENCE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/*───────────────────────────────────────────────*/
/* Configuration                                 */
/*───────────────────────────────────────────────*/

#define SG_WINDOW_SIZE        100
#define SG_RAW_FEATURES       7      /* qw,qx,qy,qz,gx,gy,gz */
#define SG_ENG_FEATURES       9
#define SG_NUM_CLASSES        3

/*───────────────────────────────────────────────*/
/* Posture States                                */
/*───────────────────────────────────────────────*/

typedef enum
{
    SG_STATE_ALERT = 0,
    SG_STATE_FATIGUING,
    SG_STATE_FATIGUED

} sg_state_t;

/*───────────────────────────────────────────────*/
/* Inference Result                              */
/*───────────────────────────────────────────────*/

typedef struct
{
    /* CNN outputs */

    float cnn_score;

    float state_probs[SG_NUM_CLASSES];

    sg_state_t state;

    /* Hybrid score */

    float hybrid_score;

} sg_result_t;

/*───────────────────────────────────────────────*/
/* API                                           */
/*───────────────────────────────────────────────*/

/**
 * Initialize TensorFlow Lite Micro model.
 *
 * Returns:
 *   0  Success
 *  -1  Failure
 */
int sg_model_init(void);

/**
 * Run posture inference.
 *
 * Parameters:
 *   window           100 x 7 quaternion/gyro window
 *   pitch_deg        Current pitch
 *   roll_deg         Current roll
 *   bad_duration_s   Time in poor posture
 *   result           Output structure
 *
 * Returns:
 *   0  Success
 *  -1  Failure
 */
int sg_run_inference(
    const float window[SG_WINDOW_SIZE][SG_RAW_FEATURES],
    float pitch_deg,
    float roll_deg,
    uint32_t bad_duration_s,
    sg_result_t *result
);

#ifdef __cplusplus
}
#endif

#endif /* SG_INFERENCE_H */