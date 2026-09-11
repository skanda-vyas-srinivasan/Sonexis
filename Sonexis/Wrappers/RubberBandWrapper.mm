#import "RubberBandWrapper.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>

#include "rubberband-c.h"

@interface RubberBandWrapper ()
@end

@implementation RubberBandWrapper {
    RubberBandState _state;
    int _channels;
    double _sampleRate;
    double _pitchScale;
    double _lastAppliedPitchScale;
    std::vector<float> _inputDeinterleaved;
    std::vector<float> _outputDeinterleaved;
    std::vector<float *> _inputPointers;
    std::vector<float *> _outputPointers;
    std::vector<float> _outputInterleaved;
    std::vector<float> _inputFifo;
    size_t _inputRead;
    size_t _inputWrite;
    size_t _inputSize;
    std::vector<float> _outputFifo;
    size_t _outputRead;
    size_t _outputWrite;
    size_t _outputSize;
    int _minProcessFrames;
    bool _isPrimed;
    bool _needsStartPadding;
    size_t _startDelayRemaining;
    float _wetMix;
}

static void ensureRingCapacity(
    std::vector<float> &buffer,
    size_t &readIndex,
    size_t &writeIndex,
    size_t &size,
    size_t additionalSamples
) {
    const size_t capacity = buffer.size();
    if (capacity >= size + additionalSamples) {
        return;
    }

    size_t newCapacity = capacity > 0 ? capacity * 2 : 1024;
    if (newCapacity < size + additionalSamples) {
        newCapacity = size + additionalSamples;
    }

    std::vector<float> newBuffer(newCapacity);
    if (capacity > 0 && size > 0) {
        for (size_t i = 0; i < size; i++) {
            newBuffer[i] = buffer[(readIndex + i) % capacity];
        }
    }
    buffer.swap(newBuffer);
    readIndex = 0;
    writeIndex = size;
}

static void ringWrite(
    std::vector<float> &buffer,
    size_t &readIndex,
    size_t &writeIndex,
    size_t &size,
    const float *data,
    size_t count
) {
    ensureRingCapacity(buffer, readIndex, writeIndex, size, count);
    const size_t capacity = buffer.size();
    const size_t first = std::min(count, capacity - writeIndex);
    if (first > 0) {
        std::memcpy(buffer.data() + writeIndex, data, first * sizeof(float));
    }
    const size_t remaining = count - first;
    if (remaining > 0) {
        std::memcpy(buffer.data(), data + first, remaining * sizeof(float));
    }
    writeIndex = (writeIndex + count) % capacity;
    size += count;
}

- (instancetype)initWithSampleRate:(double)sampleRate channels:(int)channels {
    self = [super init];
    if (self) {
        _state = nullptr;
        _channels = channels;
        _sampleRate = sampleRate;
        _pitchScale = 1.0;
        _lastAppliedPitchScale = 1.0;
        _minProcessFrames = 8192;
        _isPrimed = false;
        _inputRead = 0;
        _inputWrite = 0;
        _inputSize = 0;
        _outputRead = 0;
        _outputWrite = 0;
        _outputSize = 0;
        [self configureWithSampleRate:sampleRate channels:channels];
    }
    return self;
}

- (void)dealloc {
    if (_state) {
        rubberband_delete(_state);
        _state = nullptr;
    }
}

- (void)configureWithSampleRate:(double)sampleRate channels:(int)channels {
    if (channels <= 0 || sampleRate <= 0) {
        return;
    }

    if (_state && (_channels == channels) && (_sampleRate == sampleRate)) {
        return;
    }

    if (_state) {
        rubberband_delete(_state);
        _state = nullptr;
    }

    _channels = channels;
    _sampleRate = sampleRate;

    RubberBandOptions options = RubberBandOptionProcessRealTime |
        RubberBandOptionPitchHighQuality |
        RubberBandOptionEngineFiner |
        RubberBandOptionTransientsSmooth |
        RubberBandOptionPhaseLaminar |
        RubberBandOptionWindowLong |
        RubberBandOptionChannelsTogether;

    _state = rubberband_new((unsigned int)sampleRate,
                            (unsigned int)channels,
                            options,
                            1.0,
                            _pitchScale);
    _lastAppliedPitchScale = _pitchScale;

    rubberband_set_max_process_size(_state, 8192);
    _inputFifo.clear();
    _outputFifo.clear();
    _inputRead = 0;
    _inputWrite = 0;
    _inputSize = 0;
    _outputRead = 0;
    _outputWrite = 0;
    _outputSize = 0;
    _isPrimed = false;
    _needsStartPadding = true;
    _startDelayRemaining = 0;
    _wetMix = 0.0f;
}

- (void)setPitchSemitones:(double)semitones {
    if (!std::isfinite(semitones)) {
        semitones = 0.0;
    }
    semitones = std::max(-12.0, std::min(12.0, semitones));
    double scale = std::pow(2.0, semitones / 12.0);
    if (!std::isfinite(scale) || scale <= 0.0) {
        scale = 1.0;
    }
    if (scale == _pitchScale) {
        return;
    }
    _pitchScale = scale;
    if (_state && _lastAppliedPitchScale != scale) {
        rubberband_set_pitch_scale(_state, _pitchScale);
        _lastAppliedPitchScale = _pitchScale;
    }
}

- (void)setMinimumProcessFrames:(int)frames {
    const int clamped = std::max(256, frames);
    if (_minProcessFrames == clamped) {
        return;
    }
    _minProcessFrames = clamped;
    _isPrimed = false;
    _wetMix = 0.0f;
}

- (int)processInput:(const float *)input
             frames:(int)frames
           channels:(int)channels
             output:(float *)output
    outputCapacity:(int)outputCapacity {
    if (!_state || !input || !output || frames <= 0 || outputCapacity <= 0) {
        return 0;
    }

    if (channels != _channels) {
        [self configureWithSampleRate:_sampleRate channels:channels];
    }

    if (_needsStartPadding) {
        // Rubber Band real-time mode leaves start alignment to its caller.
        // Query after the initial pitch ratio has been set, pad its input, and
        // discard the corresponding output delay before crossfading to wet.
        const size_t padSamples = (size_t)rubberband_get_preferred_start_pad(_state) * channels;
        if (padSamples > 0) {
            _inputDeinterleaved.assign(padSamples, 0.0f);
            ringWrite(_inputFifo, _inputRead, _inputWrite, _inputSize,
                      _inputDeinterleaved.data(), padSamples);
        }
        _startDelayRemaining = rubberband_get_start_delay(_state);
        _needsStartPadding = false;
    }

    const int totalSamples = frames * channels;
    ringWrite(_inputFifo, _inputRead, _inputWrite, _inputSize, input, (size_t)totalSamples);

    const int processFrames = std::max(_minProcessFrames, frames);
    const size_t requiredSamples = (size_t)processFrames * (size_t)channels;

    while (_inputSize >= requiredSamples) {
        const int chunkFrames = processFrames;
        const int chunkSamples = chunkFrames * channels;
        if ((int)_inputDeinterleaved.size() < chunkSamples) {
            _inputDeinterleaved.resize(chunkSamples);
        }
        if ((int)_outputDeinterleaved.size() < chunkSamples) {
            _outputDeinterleaved.resize(chunkSamples);
        }
        if ((int)_outputInterleaved.size() < chunkSamples) {
            _outputInterleaved.resize(chunkSamples);
        }

        _inputPointers.assign(channels, nullptr);
        _outputPointers.assign(channels, nullptr);

        for (int ch = 0; ch < channels; ch++) {
            _inputPointers[ch] = _inputDeinterleaved.data() + (size_t)ch * chunkFrames;
            _outputPointers[ch] = _outputDeinterleaved.data() + (size_t)ch * chunkFrames;
        }

        const size_t inputCapacity = _inputFifo.size();
        for (int frame = 0; frame < chunkFrames; frame++) {
            for (int ch = 0; ch < channels; ch++) {
                const size_t sampleIndex = (size_t)frame * (size_t)channels + (size_t)ch;
                const size_t ringIndex = (_inputRead + sampleIndex) % inputCapacity;
                const float inputValue = _inputFifo[ringIndex];
                _inputPointers[ch][frame] = std::isfinite(inputValue) ? inputValue : 0.0f;
            }
        }

        if (_lastAppliedPitchScale != _pitchScale) {
            rubberband_set_pitch_scale(_state, _pitchScale);
            _lastAppliedPitchScale = _pitchScale;
        }
        rubberband_process(_state, (const float *const *)_inputPointers.data(), (unsigned int)chunkFrames, 0);

        int available = rubberband_available(_state);
        while (available > 0) {
            int toRetrieve = std::min(available, chunkFrames);
            const int retrieved = (int)rubberband_retrieve(_state, _outputPointers.data(), (unsigned int)toRetrieve);
            if (retrieved <= 0) { break; }
            const int discard = (int)std::min(_startDelayRemaining, (size_t)retrieved);
            _startDelayRemaining -= discard;
            const int retrievedSamples = (retrieved - discard) * channels;
            int outputIndex = 0;
            for (int frame = discard; frame < retrieved; frame++) {
                for (int ch = 0; ch < channels; ch++) {
                    const float outputValue = _outputPointers[ch][frame];
                    _outputInterleaved[outputIndex++] = std::isfinite(outputValue) ? outputValue : 0.0f;
                }
            }
            if (retrievedSamples > 0) {
                ringWrite(
                    _outputFifo,
                    _outputRead,
                    _outputWrite,
                    _outputSize,
                    _outputInterleaved.data(),
                    (size_t)retrievedSamples
                );
            }
            available = rubberband_available(_state);
        }

        _inputRead = (_inputRead + requiredSamples) % _inputFifo.size();
        _inputSize -= requiredSamples;
    }

    const int availableOutFrames = (int)(_outputSize / (size_t)channels);
    const int prebufferFrames = _minProcessFrames * 2;
    if (!_isPrimed) {
        if (availableOutFrames >= prebufferFrames) {
            _isPrimed = true;
        } else {
            // No pitch output yet: keep the current input audible. Do not use
            // signal level to decide readiness; intentional silence is valid.
            for (int frame = 0; frame < outputCapacity; frame++) {
                for (int ch = 0; ch < channels; ch++) {
                    const float dry = frame < frames ? input[frame * channels + ch] : 0.0f;
                    output[frame * channels + ch] = std::isfinite(dry) ? dry : 0.0f;
                }
            }
            return outputCapacity;
        }
    }

    const int toCopyFrames = std::min(outputCapacity, availableOutFrames);
    const float fadeStep = (float)(1.0 / std::max(1.0, _sampleRate * 0.02));

    for (int frame = 0; frame < outputCapacity; frame++) {
        if (frame < toCopyFrames) { _wetMix = std::min(1.0f, _wetMix + fadeStep); }
        else { _wetMix = 0.0f; }
        for (int ch = 0; ch < channels; ch++) {
            float value;
            if (frame < toCopyFrames) {
                const size_t sampleIndex = (size_t)frame * (size_t)channels + (size_t)ch;
                const size_t ringIndex = (_outputRead + sampleIndex) % _outputFifo.size();
                value = _outputFifo[ringIndex];
            } else {
                value = 0.0f;
            }
            if (!std::isfinite(value)) {
                value = 0.0f;
            }
            const float dry = frame < frames ? input[frame * channels + ch] : 0.0f;
            output[frame * channels + ch] = (std::isfinite(dry) ? dry : 0.0f) * (1.0f - _wetMix) + value * _wetMix;
        }
    }

    if (toCopyFrames > 0) {
        const size_t consumedSamples = (size_t)toCopyFrames * (size_t)channels;
        _outputRead = (_outputRead + consumedSamples) % _outputFifo.size();
        _outputSize -= consumedSamples;
    }
    if (toCopyFrames < outputCapacity) { _isPrimed = false; }

    return outputCapacity;
}

- (void)reset {
    if (_state) {
        rubberband_reset(_state);
    }
    _inputFifo.clear();
    _outputFifo.clear();
    _inputRead = 0;
    _inputWrite = 0;
    _inputSize = 0;
    _outputRead = 0;
    _outputWrite = 0;
    _outputSize = 0;
    _isPrimed = false;
    _needsStartPadding = true;
    _startDelayRemaining = 0;
    _wetMix = 0.0f;
}

@end
