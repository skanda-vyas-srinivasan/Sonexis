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

uint32_t SonexisAudioRingBufferReadToAudioBufferList(
    SonexisAudioRingBuffer *ringBuffer,
    AudioBufferList *outputData
);

void SonexisAudioRingBufferSetReadEnabled(SonexisAudioRingBuffer *ringBuffer, bool enabled);
void SonexisAudioRingBufferConfigurePitchShift(
    SonexisAudioRingBuffer *ringBuffer,
    bool enabled,
    float semitones
);
uint32_t SonexisAudioRingBufferGetFillFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetDroppedFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetUnderflowFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetWrittenFrames(SonexisAudioRingBuffer *ringBuffer);
uint64_t SonexisAudioRingBufferGetReadFrames(SonexisAudioRingBuffer *ringBuffer);
uint32_t SonexisAudioRingBufferGetLastInputPeakPPM(SonexisAudioRingBuffer *ringBuffer);
void SonexisAudioRingBufferSetGainImmediate(SonexisAudioRingBuffer *ringBuffer, float gain);
void SonexisAudioRingBufferRequestGainRamp(SonexisAudioRingBuffer *ringBuffer, float targetGain, uint32_t rampFrames);
uint32_t SonexisAudioRingBufferGetCurrentGainPPM(SonexisAudioRingBuffer *ringBuffer);

#endif
