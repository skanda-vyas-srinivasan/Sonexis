#include "RealtimeAudioRing.h"

#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

struct SonexisAudioRingBuffer {
    float *samples;
    float *pitchDelayLine;
    uint32_t capacityFrames;
    uint32_t channels;
    uint32_t pitchDelayLineFrames;
    atomic_uint writeFrame;
    atomic_uint readFrame;
    atomic_ullong droppedFrames;
    atomic_ullong underflowFrames;
    atomic_ullong writtenFrames;
    atomic_ullong readFrames;
    atomic_uint lastInputPeakPPM;
    atomic_uint requestedTargetGainPPM;
    atomic_uint requestedRampFrames;
    atomic_uint gainRampRequestID;
    atomic_uint currentGainPPM;
    atomic_bool readEnabled;
    atomic_bool pitchShiftEnabled;
    float currentGain;
    float rampTargetGain;
    uint32_t rampRemainingFrames;
    uint32_t appliedGainRampRequestID;
    uint32_t pitchWriteFrame;
    float pitchPhase;
    float pitchPhaseIncrement;
    float pitchMinDelayFrames;
    float pitchDelayRangeFrames;
};

static float clampGain(float gain) {
    if (gain < 0.0f) {
        return 0.0f;
    }
    if (gain > 4.0f) {
        return 4.0f;
    }
    return gain;
}

static uint32_t gainToPPM(float gain) {
    return (uint32_t)(clampGain(gain) * 1000000.0f);
}

static float ppmToGain(uint32_t ppm) {
    return (float)ppm / 1000000.0f;
}

static uint32_t minimumFrameCountInAudioBufferList(const AudioBufferList *bufferList) {
    if (bufferList == NULL || bufferList->mNumberBuffers == 0) {
        return 0;
    }

    uint32_t result = UINT32_MAX;
    bool foundBuffer = false;

    for (uint32_t bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex) {
        const AudioBuffer *buffer = &bufferList->mBuffers[bufferIndex];
        if (buffer->mData == NULL || buffer->mDataByteSize == 0 || buffer->mNumberChannels == 0) {
            continue;
        }

        uint32_t bytesPerFrame = (uint32_t)sizeof(float) * buffer->mNumberChannels;
        uint32_t frames = buffer->mDataByteSize / bytesPerFrame;
        if (frames < result) {
            result = frames;
        }
        foundBuffer = true;
    }

    return foundBuffer ? result : 0;
}

static void zeroAudioBufferList(AudioBufferList *bufferList) {
    if (bufferList == NULL) {
        return;
    }

    for (uint32_t bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; ++bufferIndex) {
        AudioBuffer *buffer = &bufferList->mBuffers[bufferIndex];
        if (buffer->mData != NULL && buffer->mDataByteSize > 0) {
            memset(buffer->mData, 0, buffer->mDataByteSize);
        }
    }
}

SonexisAudioRingBuffer *SonexisAudioRingBufferCreate(uint32_t capacityFrames, uint32_t channels) {
    if (capacityFrames == 0 || channels == 0) {
        return NULL;
    }

    SonexisAudioRingBuffer *ringBuffer = calloc(1, sizeof(SonexisAudioRingBuffer));
    if (ringBuffer == NULL) {
        return NULL;
    }

    ringBuffer->samples = calloc((size_t)capacityFrames * channels, sizeof(float));
    if (ringBuffer->samples == NULL) {
        free(ringBuffer);
        return NULL;
    }

    ringBuffer->pitchDelayLineFrames = 4096;
    ringBuffer->pitchDelayLine = calloc(
        (size_t)ringBuffer->pitchDelayLineFrames * channels,
        sizeof(float)
    );
    if (ringBuffer->pitchDelayLine == NULL) {
        free(ringBuffer->samples);
        free(ringBuffer);
        return NULL;
    }

    ringBuffer->capacityFrames = capacityFrames;
    ringBuffer->channels = channels;
    atomic_init(&ringBuffer->writeFrame, 0);
    atomic_init(&ringBuffer->readFrame, 0);
    atomic_init(&ringBuffer->droppedFrames, 0);
    atomic_init(&ringBuffer->underflowFrames, 0);
    atomic_init(&ringBuffer->writtenFrames, 0);
    atomic_init(&ringBuffer->readFrames, 0);
    atomic_init(&ringBuffer->lastInputPeakPPM, 0);
    atomic_init(&ringBuffer->requestedTargetGainPPM, gainToPPM(1.0f));
    atomic_init(&ringBuffer->requestedRampFrames, 0);
    atomic_init(&ringBuffer->gainRampRequestID, 0);
    atomic_init(&ringBuffer->currentGainPPM, gainToPPM(1.0f));
    atomic_init(&ringBuffer->readEnabled, true);
    atomic_init(&ringBuffer->pitchShiftEnabled, false);
    ringBuffer->currentGain = 1.0f;
    ringBuffer->rampTargetGain = 1.0f;
    ringBuffer->rampRemainingFrames = 0;
    ringBuffer->appliedGainRampRequestID = 0;
    ringBuffer->pitchWriteFrame = 0;
    ringBuffer->pitchPhase = 0.0f;
    ringBuffer->pitchPhaseIncrement = 0.0f;
    ringBuffer->pitchMinDelayFrames = 256.0f;
    ringBuffer->pitchDelayRangeFrames = 1792.0f;

    return ringBuffer;
}

void SonexisAudioRingBufferDestroy(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return;
    }

    free(ringBuffer->pitchDelayLine);
    free(ringBuffer->samples);
    free(ringBuffer);
}

static float readPitchDelayLine(
    SonexisAudioRingBuffer *ringBuffer,
    uint32_t channel,
    float delayFrames
) {
    float readPosition = (float)ringBuffer->pitchWriteFrame - delayFrames;
    while (readPosition < 0.0f) {
        readPosition += (float)ringBuffer->pitchDelayLineFrames;
    }

    uint32_t index0 = (uint32_t)readPosition;
    uint32_t index1 = (index0 + 1) % ringBuffer->pitchDelayLineFrames;
    float fraction = readPosition - (float)index0;
    float sample0 = ringBuffer->pitchDelayLine[(index0 * ringBuffer->channels) + channel];
    float sample1 = ringBuffer->pitchDelayLine[(index1 * ringBuffer->channels) + channel];
    return sample0 + ((sample1 - sample0) * fraction);
}

static float processPitchShiftSample(
    SonexisAudioRingBuffer *ringBuffer,
    float inputSample,
    uint32_t channel,
    float phase
) {
    ringBuffer->pitchDelayLine[
        (ringBuffer->pitchWriteFrame * ringBuffer->channels) + channel
    ] = inputSample;

    float phaseB = phase + 0.5f;
    if (phaseB >= 1.0f) {
        phaseB -= 1.0f;
    }

    float delayA = ringBuffer->pitchMinDelayFrames +
        ((1.0f - phase) * ringBuffer->pitchDelayRangeFrames);
    float delayB = ringBuffer->pitchMinDelayFrames +
        ((1.0f - phaseB) * ringBuffer->pitchDelayRangeFrames);
    float windowA = sinf((float)M_PI * phase);
    float windowB = sinf((float)M_PI * phaseB);
    float sampleA = readPitchDelayLine(ringBuffer, channel, delayA);
    float sampleB = readPitchDelayLine(ringBuffer, channel, delayB);
    float denominator = windowA + windowB;

    if (denominator <= 0.000001f) {
        return 0.0f;
    }
    return ((sampleA * windowA) + (sampleB * windowB)) / denominator;
}

uint32_t SonexisAudioRingBufferWriteFromAudioBufferList(
    SonexisAudioRingBuffer *ringBuffer,
    const AudioBufferList *inputData
) {
    if (ringBuffer == NULL || inputData == NULL) {
        return 0;
    }

    uint32_t incomingFrames = minimumFrameCountInAudioBufferList(inputData);
    if (incomingFrames == 0) {
        return 0;
    }

    uint32_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_relaxed);
    uint32_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_acquire);
    uint32_t readableFrames = writeFrame - readFrame;
    uint32_t writableFrames = ringBuffer->capacityFrames - readableFrames;
    uint32_t framesToWrite = incomingFrames < writableFrames ? incomingFrames : writableFrames;

    if (framesToWrite < incomingFrames) {
        atomic_fetch_add_explicit(
            &ringBuffer->droppedFrames,
            (unsigned long long)(incomingFrames - framesToWrite),
            memory_order_relaxed
        );
    }

    float peak = 0.0f;
    bool pitchShiftEnabled = atomic_load_explicit(
        &ringBuffer->pitchShiftEnabled,
        memory_order_acquire
    );
    uint32_t requestID = atomic_load_explicit(&ringBuffer->gainRampRequestID, memory_order_acquire);
    if (requestID != ringBuffer->appliedGainRampRequestID) {
        ringBuffer->appliedGainRampRequestID = requestID;
        ringBuffer->rampTargetGain = ppmToGain(
            atomic_load_explicit(&ringBuffer->requestedTargetGainPPM, memory_order_relaxed)
        );
        ringBuffer->rampRemainingFrames = atomic_load_explicit(
            &ringBuffer->requestedRampFrames,
            memory_order_relaxed
        );
        if (ringBuffer->rampRemainingFrames == 0) {
            ringBuffer->currentGain = ringBuffer->rampTargetGain;
        }
    }

    for (uint32_t frame = 0; frame < framesToWrite; ++frame) {
        uint32_t outputFrame = (writeFrame + frame) % ringBuffer->capacityFrames;
        uint32_t outputBase = outputFrame * ringBuffer->channels;
        uint32_t outputChannel = 0;
        float frameGain = ringBuffer->currentGain;
        float pitchPhase = ringBuffer->pitchPhase;

        if (ringBuffer->rampRemainingFrames > 0) {
            float step = (ringBuffer->rampTargetGain - ringBuffer->currentGain) /
                (float)ringBuffer->rampRemainingFrames;
            ringBuffer->currentGain += step;
            ringBuffer->rampRemainingFrames -= 1;
            frameGain = ringBuffer->currentGain;

            if (ringBuffer->rampRemainingFrames == 0) {
                ringBuffer->currentGain = ringBuffer->rampTargetGain;
                frameGain = ringBuffer->currentGain;
            }
        }

        for (uint32_t bufferIndex = 0; bufferIndex < inputData->mNumberBuffers; ++bufferIndex) {
            const AudioBuffer *buffer = &inputData->mBuffers[bufferIndex];
            if (buffer->mData == NULL || buffer->mNumberChannels == 0) {
                continue;
            }

            const float *samples = (const float *)buffer->mData;
            uint32_t bufferChannels = buffer->mNumberChannels;

            for (uint32_t channel = 0; channel < bufferChannels; ++channel) {
                if (outputChannel >= ringBuffer->channels) {
                    break;
                }

                float inputSample = samples[(frame * bufferChannels) + channel];
                float absoluteSample = fabsf(inputSample);
                if (absoluteSample > peak) {
                    peak = absoluteSample;
                }
                float processedSample = inputSample;
                if (pitchShiftEnabled) {
                    processedSample = processPitchShiftSample(
                        ringBuffer,
                        inputSample,
                        outputChannel,
                        pitchPhase
                    );
                }
                ringBuffer->samples[outputBase + outputChannel] = processedSample * frameGain;
                outputChannel += 1;
            }
        }

        while (outputChannel < ringBuffer->channels) {
            float processedSample = 0.0f;
            if (pitchShiftEnabled) {
                processedSample = processPitchShiftSample(
                    ringBuffer,
                    0.0f,
                    outputChannel,
                    pitchPhase
                );
            }
            ringBuffer->samples[outputBase + outputChannel] = processedSample * frameGain;
            outputChannel += 1;
        }

        if (pitchShiftEnabled) {
            ringBuffer->pitchWriteFrame =
                (ringBuffer->pitchWriteFrame + 1) % ringBuffer->pitchDelayLineFrames;
            ringBuffer->pitchPhase += ringBuffer->pitchPhaseIncrement;
            while (ringBuffer->pitchPhase >= 1.0f) {
                ringBuffer->pitchPhase -= 1.0f;
            }
        }
    }

    uint32_t peakPPM = (uint32_t)fminf(peak * 1000000.0f, 1000000.0f);
    atomic_store_explicit(&ringBuffer->lastInputPeakPPM, peakPPM, memory_order_relaxed);
    atomic_fetch_add_explicit(
        &ringBuffer->writtenFrames,
        (unsigned long long)framesToWrite,
        memory_order_relaxed
    );
    atomic_store_explicit(
        &ringBuffer->currentGainPPM,
        gainToPPM(ringBuffer->currentGain),
        memory_order_relaxed
    );
    atomic_store_explicit(&ringBuffer->writeFrame, writeFrame + framesToWrite, memory_order_release);
    return framesToWrite;
}

uint32_t SonexisAudioRingBufferReadToAudioBufferList(
    SonexisAudioRingBuffer *ringBuffer,
    AudioBufferList *outputData
) {
    if (ringBuffer == NULL || outputData == NULL) {
        return 0;
    }

    uint32_t requestedFrames = minimumFrameCountInAudioBufferList(outputData);
    if (requestedFrames == 0) {
        zeroAudioBufferList(outputData);
        return 0;
    }

    zeroAudioBufferList(outputData);
    if (!atomic_load_explicit(&ringBuffer->readEnabled, memory_order_acquire)) {
        return 0;
    }

    uint32_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_acquire);
    uint32_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_relaxed);
    uint32_t readableFrames = writeFrame - readFrame;
    uint32_t framesToRead = requestedFrames < readableFrames ? requestedFrames : readableFrames;

    if (framesToRead < requestedFrames) {
        atomic_fetch_add_explicit(
            &ringBuffer->underflowFrames,
            (unsigned long long)(requestedFrames - framesToRead),
            memory_order_relaxed
        );
    }

    for (uint32_t frame = 0; frame < framesToRead; ++frame) {
        uint32_t inputFrame = (readFrame + frame) % ringBuffer->capacityFrames;
        uint32_t inputBase = inputFrame * ringBuffer->channels;
        uint32_t inputChannel = 0;

        for (uint32_t bufferIndex = 0; bufferIndex < outputData->mNumberBuffers; ++bufferIndex) {
            AudioBuffer *buffer = &outputData->mBuffers[bufferIndex];
            if (buffer->mData == NULL || buffer->mNumberChannels == 0) {
                continue;
            }

            float *samples = (float *)buffer->mData;
            uint32_t bufferChannels = buffer->mNumberChannels;

            for (uint32_t channel = 0; channel < bufferChannels; ++channel) {
                if (inputChannel >= ringBuffer->channels) {
                    break;
                }

                samples[(frame * bufferChannels) + channel] =
                    ringBuffer->samples[inputBase + inputChannel];
                inputChannel += 1;
            }
        }
    }

    atomic_fetch_add_explicit(
        &ringBuffer->readFrames,
        (unsigned long long)framesToRead,
        memory_order_relaxed
    );
    atomic_store_explicit(&ringBuffer->readFrame, readFrame + framesToRead, memory_order_release);
    return framesToRead;
}

void SonexisAudioRingBufferSetReadEnabled(SonexisAudioRingBuffer *ringBuffer, bool enabled) {
    if (ringBuffer == NULL) {
        return;
    }

    atomic_store_explicit(&ringBuffer->readEnabled, enabled, memory_order_release);
}

void SonexisAudioRingBufferConfigurePitchShift(
    SonexisAudioRingBuffer *ringBuffer,
    bool enabled,
    float semitones
) {
    if (ringBuffer == NULL) {
        return;
    }

    if (!enabled || semitones <= 0.0f) {
        ringBuffer->pitchPhase = 0.0f;
        ringBuffer->pitchPhaseIncrement = 0.0f;
        ringBuffer->pitchWriteFrame = 0;
        memset(
            ringBuffer->pitchDelayLine,
            0,
            (size_t)ringBuffer->pitchDelayLineFrames *
                ringBuffer->channels *
                sizeof(float)
        );
        atomic_store_explicit(&ringBuffer->pitchShiftEnabled, false, memory_order_release);
        return;
    }

    float safeSemitones = semitones;
    if (safeSemitones > 12.0f) {
        safeSemitones = 12.0f;
    }

    float pitchRatio = powf(2.0f, safeSemitones / 12.0f);
    float phaseIncrement = (pitchRatio - 1.0f) / ringBuffer->pitchDelayRangeFrames;

    memset(
        ringBuffer->pitchDelayLine,
        0,
        (size_t)ringBuffer->pitchDelayLineFrames *
            ringBuffer->channels *
            sizeof(float)
    );
    ringBuffer->pitchPhase = 0.0f;
    ringBuffer->pitchPhaseIncrement = phaseIncrement;
    ringBuffer->pitchWriteFrame = 0;
    atomic_store_explicit(&ringBuffer->pitchShiftEnabled, true, memory_order_release);
}

uint32_t SonexisAudioRingBufferGetFillFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    uint32_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_acquire);
    uint32_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_acquire);
    return writeFrame - readFrame;
}

uint64_t SonexisAudioRingBufferGetDroppedFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->droppedFrames, memory_order_relaxed);
}

uint64_t SonexisAudioRingBufferGetUnderflowFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->underflowFrames, memory_order_relaxed);
}

uint64_t SonexisAudioRingBufferGetWrittenFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->writtenFrames, memory_order_relaxed);
}

uint64_t SonexisAudioRingBufferGetReadFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->readFrames, memory_order_relaxed);
}

uint32_t SonexisAudioRingBufferGetLastInputPeakPPM(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->lastInputPeakPPM, memory_order_relaxed);
}

void SonexisAudioRingBufferSetGainImmediate(SonexisAudioRingBuffer *ringBuffer, float gain) {
    if (ringBuffer == NULL) {
        return;
    }

    float clampedGain = clampGain(gain);
    uint32_t gainPPM = gainToPPM(clampedGain);
    ringBuffer->currentGain = clampedGain;
    ringBuffer->rampTargetGain = clampedGain;
    ringBuffer->rampRemainingFrames = 0;
    atomic_store_explicit(&ringBuffer->requestedTargetGainPPM, gainPPM, memory_order_relaxed);
    atomic_store_explicit(&ringBuffer->requestedRampFrames, 0, memory_order_relaxed);
    atomic_store_explicit(&ringBuffer->currentGainPPM, gainPPM, memory_order_relaxed);
    atomic_fetch_add_explicit(&ringBuffer->gainRampRequestID, 1, memory_order_release);
}

void SonexisAudioRingBufferRequestGainRamp(SonexisAudioRingBuffer *ringBuffer, float targetGain, uint32_t rampFrames) {
    if (ringBuffer == NULL) {
        return;
    }

    atomic_store_explicit(
        &ringBuffer->requestedTargetGainPPM,
        gainToPPM(targetGain),
        memory_order_relaxed
    );
    atomic_store_explicit(&ringBuffer->requestedRampFrames, rampFrames, memory_order_relaxed);
    atomic_fetch_add_explicit(&ringBuffer->gainRampRequestID, 1, memory_order_release);
}

uint32_t SonexisAudioRingBufferGetCurrentGainPPM(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->currentGainPPM, memory_order_relaxed);
}
