#include "RealtimeAudioRing.h"

#include <stdatomic.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

struct SonexisAudioRingBuffer {
    float *samples;
    uint32_t capacityFrames;
    uint32_t channels;
    atomic_ullong writeFrame;
    atomic_ullong readFrame;
    atomic_ullong droppedFrames;
    atomic_ullong underflowFrames;
    atomic_ullong writtenFrames;
    atomic_ullong readFrames;
    atomic_uint lastInputPeakPPM;
    atomic_uint targetFillFrames;
    atomic_uint requestedTargetGainPPM;
    atomic_uint requestedRampFrames;
    atomic_uint gainRampRequestID;
    atomic_uint currentGainPPM;
    atomic_bool readEnabled;
    float currentGain;
    float rampTargetGain;
    uint32_t rampRemainingFrames;
    uint32_t appliedGainRampRequestID;
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

    ringBuffer->capacityFrames = capacityFrames;
    ringBuffer->channels = channels;
    atomic_init(&ringBuffer->writeFrame, 0);
    atomic_init(&ringBuffer->readFrame, 0);
    atomic_init(&ringBuffer->droppedFrames, 0);
    atomic_init(&ringBuffer->underflowFrames, 0);
    atomic_init(&ringBuffer->writtenFrames, 0);
    atomic_init(&ringBuffer->readFrames, 0);
    atomic_init(&ringBuffer->lastInputPeakPPM, 0);
    atomic_init(&ringBuffer->targetFillFrames, 0);
    atomic_init(&ringBuffer->requestedTargetGainPPM, gainToPPM(1.0f));
    atomic_init(&ringBuffer->requestedRampFrames, 0);
    atomic_init(&ringBuffer->gainRampRequestID, 0);
    atomic_init(&ringBuffer->currentGainPPM, gainToPPM(1.0f));
    atomic_init(&ringBuffer->readEnabled, true);
    ringBuffer->currentGain = 1.0f;
    ringBuffer->rampTargetGain = 1.0f;
    ringBuffer->rampRemainingFrames = 0;
    ringBuffer->appliedGainRampRequestID = 0;

    return ringBuffer;
}

static void copyRingFrameToAudioBufferList(
    const SonexisAudioRingBuffer *ringBuffer,
    AudioBufferList *outputData,
    uint32_t outputFrame,
    uint64_t ringFrame
) {
    uint32_t inputBase = (uint32_t)(ringFrame % ringBuffer->capacityFrames) * ringBuffer->channels;
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

            samples[(outputFrame * bufferChannels) + channel] =
                ringBuffer->samples[inputBase + inputChannel];
            inputChannel += 1;
        }
    }
}

static void copyRingFrameToInterleaved(
    const SonexisAudioRingBuffer *ringBuffer,
    float *outputSamples,
    uint32_t outputFrame,
    uint64_t ringFrame
) {
    uint32_t inputBase = (uint32_t)(ringFrame % ringBuffer->capacityFrames) * ringBuffer->channels;
    uint32_t outputBase = outputFrame * ringBuffer->channels;

    for (uint32_t channel = 0; channel < ringBuffer->channels; ++channel) {
        outputSamples[outputBase + channel] = ringBuffer->samples[inputBase + channel];
    }
}

void SonexisAudioRingBufferDestroy(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return;
    }

    free(ringBuffer->samples);
    free(ringBuffer);
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

    uint64_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_relaxed);
    uint64_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_acquire);
    uint64_t readableFrameCount = writeFrame - readFrame;
    if (readableFrameCount > ringBuffer->capacityFrames) {
        readableFrameCount = ringBuffer->capacityFrames;
    }
    uint32_t writableFrames = ringBuffer->capacityFrames - (uint32_t)readableFrameCount;
    uint32_t framesToWrite = incomingFrames < writableFrames ? incomingFrames : writableFrames;

    if (framesToWrite < incomingFrames) {
        atomic_fetch_add_explicit(
            &ringBuffer->droppedFrames,
            (unsigned long long)(incomingFrames - framesToWrite),
            memory_order_relaxed
        );
    }

    float peak = 0.0f;
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
        uint32_t outputFrame = (uint32_t)((writeFrame + frame) % ringBuffer->capacityFrames);
        uint32_t outputBase = outputFrame * ringBuffer->channels;
        uint32_t outputChannel = 0;
        float frameGain = ringBuffer->currentGain;

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
                ringBuffer->samples[outputBase + outputChannel] = inputSample * frameGain;
                outputChannel += 1;
            }
        }

        while (outputChannel < ringBuffer->channels) {
            ringBuffer->samples[outputBase + outputChannel] = 0.0f;
            outputChannel += 1;
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
    atomic_store_explicit(
        &ringBuffer->writeFrame,
        writeFrame + (uint64_t)framesToWrite,
        memory_order_release
    );
    return framesToWrite;
}

uint32_t SonexisAudioRingBufferWriteInterleaved(
    SonexisAudioRingBuffer *ringBuffer,
    const float *inputSamples,
    uint32_t frames
) {
    if (ringBuffer == NULL || inputSamples == NULL || frames == 0) {
        return 0;
    }

    uint64_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_relaxed);
    uint64_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_acquire);
    uint64_t readableFrameCount = writeFrame - readFrame;
    if (readableFrameCount > ringBuffer->capacityFrames) {
        readableFrameCount = ringBuffer->capacityFrames;
    }
    uint32_t writableFrames = ringBuffer->capacityFrames - (uint32_t)readableFrameCount;
    uint32_t framesToWrite = frames < writableFrames ? frames : writableFrames;

    if (framesToWrite < frames) {
        atomic_fetch_add_explicit(
            &ringBuffer->droppedFrames,
            (unsigned long long)(frames - framesToWrite),
            memory_order_relaxed
        );
    }

    float peak = 0.0f;
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
        uint32_t outputFrame = (uint32_t)((writeFrame + frame) % ringBuffer->capacityFrames);
        uint32_t outputBase = outputFrame * ringBuffer->channels;
        float frameGain = ringBuffer->currentGain;

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

        for (uint32_t channel = 0; channel < ringBuffer->channels; ++channel) {
            float inputSample = inputSamples[(frame * ringBuffer->channels) + channel];
            float absoluteSample = fabsf(inputSample);
            if (absoluteSample > peak) {
                peak = absoluteSample;
            }

            ringBuffer->samples[outputBase + channel] = inputSample * frameGain;
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
    atomic_store_explicit(
        &ringBuffer->writeFrame,
        writeFrame + (uint64_t)framesToWrite,
        memory_order_release
    );
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

    uint64_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_acquire);
    uint64_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_relaxed);
    uint64_t readableFrameCount = writeFrame - readFrame;
    if (readableFrameCount > ringBuffer->capacityFrames) {
        readableFrameCount = ringBuffer->capacityFrames;
    }
    uint32_t readableFrames = (uint32_t)readableFrameCount;
    uint32_t targetFillFrames = atomic_load_explicit(
        &ringBuffer->targetFillFrames,
        memory_order_relaxed
    );
    uint32_t framesToConsume = requestedFrames < readableFrames ? requestedFrames : readableFrames;

    if (targetFillFrames > 0 && readableFrames > 0 && requestedFrames > 1) {
        if (readableFrames >= requestedFrames && readableFrames <= targetFillFrames) {
            framesToConsume = requestedFrames - 1;
        } else if (readableFrames > targetFillFrames + requestedFrames) {
            framesToConsume = requestedFrames + 1;
            if (framesToConsume > readableFrames) {
                framesToConsume = readableFrames;
            }
        }
    }

    uint32_t framesToCopy = framesToConsume < requestedFrames ? framesToConsume : requestedFrames;
    if (readableFrames < requestedFrames) {
        atomic_fetch_add_explicit(
            &ringBuffer->underflowFrames,
            (unsigned long long)(requestedFrames - readableFrames),
            memory_order_relaxed
        );
    }

    for (uint32_t frame = 0; frame < framesToCopy; ++frame) {
        copyRingFrameToAudioBufferList(ringBuffer, outputData, frame, readFrame + frame);
    }

    atomic_fetch_add_explicit(
        &ringBuffer->readFrames,
        (unsigned long long)framesToConsume,
        memory_order_relaxed
    );
    atomic_store_explicit(
        &ringBuffer->readFrame,
        readFrame + (uint64_t)framesToConsume,
        memory_order_release
    );
    return framesToCopy;
}

uint32_t SonexisAudioRingBufferReadInterleaved(
    SonexisAudioRingBuffer *ringBuffer,
    float *outputSamples,
    uint32_t frames
) {
    if (ringBuffer == NULL || outputSamples == NULL || frames == 0) {
        return 0;
    }

    memset(outputSamples, 0, (size_t)frames * ringBuffer->channels * sizeof(float));
    if (!atomic_load_explicit(&ringBuffer->readEnabled, memory_order_acquire)) {
        return 0;
    }

    uint64_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_acquire);
    uint64_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_relaxed);
    uint64_t readableFrameCount = writeFrame - readFrame;
    if (readableFrameCount > ringBuffer->capacityFrames) {
        readableFrameCount = ringBuffer->capacityFrames;
    }
    uint32_t readableFrames = (uint32_t)readableFrameCount;
    uint32_t targetFillFrames = atomic_load_explicit(
        &ringBuffer->targetFillFrames,
        memory_order_relaxed
    );
    uint32_t framesToConsume = frames < readableFrames ? frames : readableFrames;

    if (targetFillFrames > 0 && readableFrames > 0 && frames > 1) {
        if (readableFrames >= frames && readableFrames <= targetFillFrames) {
            framesToConsume = frames - 1;
        } else if (readableFrames > targetFillFrames + frames) {
            framesToConsume = frames + 1;
            if (framesToConsume > readableFrames) {
                framesToConsume = readableFrames;
            }
        }
    }

    uint32_t framesToCopy = framesToConsume < frames ? framesToConsume : frames;
    if (readableFrames < frames) {
        atomic_fetch_add_explicit(
            &ringBuffer->underflowFrames,
            (unsigned long long)(frames - readableFrames),
            memory_order_relaxed
        );
    }

    for (uint32_t frame = 0; frame < framesToCopy; ++frame) {
        copyRingFrameToInterleaved(ringBuffer, outputSamples, frame, readFrame + frame);
    }

    atomic_fetch_add_explicit(
        &ringBuffer->readFrames,
        (unsigned long long)framesToConsume,
        memory_order_relaxed
    );
    atomic_store_explicit(
        &ringBuffer->readFrame,
        readFrame + (uint64_t)framesToConsume,
        memory_order_release
    );
    return framesToCopy;
}

void SonexisAudioRingBufferSetReadEnabled(SonexisAudioRingBuffer *ringBuffer, bool enabled) {
    if (ringBuffer == NULL) {
        return;
    }

    atomic_store_explicit(&ringBuffer->readEnabled, enabled, memory_order_release);
}

void SonexisAudioRingBufferSetTargetFillFrames(SonexisAudioRingBuffer *ringBuffer, uint32_t targetFillFrames) {
    if (ringBuffer == NULL) {
        return;
    }

    uint32_t boundedTarget = targetFillFrames;
    if (boundedTarget >= ringBuffer->capacityFrames) {
        boundedTarget = ringBuffer->capacityFrames > 1 ? ringBuffer->capacityFrames - 1 : 0;
    }

    atomic_store_explicit(&ringBuffer->targetFillFrames, boundedTarget, memory_order_release);
}

uint32_t SonexisAudioRingBufferGetFillFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    uint64_t writeFrame = atomic_load_explicit(&ringBuffer->writeFrame, memory_order_acquire);
    uint64_t readFrame = atomic_load_explicit(&ringBuffer->readFrame, memory_order_acquire);
    uint64_t fillFrames = writeFrame - readFrame;
    if (fillFrames > ringBuffer->capacityFrames) {
        return ringBuffer->capacityFrames;
    }
    return (uint32_t)fillFrames;
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

uint32_t SonexisAudioRingBufferGetTargetFillFrames(SonexisAudioRingBuffer *ringBuffer) {
    if (ringBuffer == NULL) {
        return 0;
    }

    return atomic_load_explicit(&ringBuffer->targetFillFrames, memory_order_relaxed);
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
