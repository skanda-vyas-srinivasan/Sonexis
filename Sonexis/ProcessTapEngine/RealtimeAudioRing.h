#ifndef RealtimeAudioRing_h
#define RealtimeAudioRing_h

#include <CoreAudio/CoreAudio.h>
#include <stdbool.h>
#include <stdint.h>

typedef struct SonexisAudioRingBuffer SonexisAudioRingBuffer;

SonexisAudioRingBuffer *SonexisAudioRingBufferCreate(uint32_t capacityFrames, uint32_t channels);
void SonexisAudioRingBufferDestroy(SonexisAudioRingBuffer *ringBuffer);

uint32_t SonexisAudioRingBufferWriteFromAudioBufferList(
    SonexisAudioRingBuffer *ringBuffer,
    const AudioBufferList *inputData
);

uint32_t SonexisAudioRingBufferWriteInterleaved(
    SonexisAudioRingBuffer *ringBuffer,
    const float *inputSamples,
    uint32_t frames
);

uint32_t SonexisAudioRingBufferReadToAudioBufferList(
    SonexisAudioRingBuffer *ringBuffer,
    AudioBufferList *outputData
);

uint32_t SonexisAudioRingBufferReadInterleaved(
    SonexisAudioRingBuffer *ringBuffer,
    float *outputSamples,
    uint32_t frames
);

void SonexisAudioRingBufferSetReadEnabled(SonexisAudioRingBuffer *ringBuffer, bool enabled);
void SonexisAudioRingBufferSetTargetFillFrames(SonexisAudioRingBuffer *ringBuffer, uint32_t targetFillFrames);
uint32_t SonexisAudioRingBufferGetFillFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetDroppedFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetUnderflowFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetWrittenFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetReadFrames(SonexisAudioRingBuffer *ringBuffer);
uint32_t SonexisAudioRingBufferGetLastInputPeakPPM(SonexisAudioRingBuffer *ringBuffer);
uint32_t SonexisAudioRingBufferGetTargetFillFrames(SonexisAudioRingBuffer *ringBuffer);
void SonexisAudioRingBufferSetGainImmediate(SonexisAudioRingBuffer *ringBuffer, float gain);
void SonexisAudioRingBufferRequestGainRamp(SonexisAudioRingBuffer *ringBuffer, float targetGain, uint32_t rampFrames);
uint32_t SonexisAudioRingBufferGetCurrentGainPPM(SonexisAudioRingBuffer *ringBuffer);

#endif
