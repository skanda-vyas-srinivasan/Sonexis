#import "RubberBandWrapper.h"

#include <algorithm>
#include <cmath>
#include <vector>

#include "rubberband-c.h"

@interface RubberBandWrapper ()
@end

@implementation RubberBandWrapper {
    RubberBandState _state;
    int _channels;
    double _sampleRate;
    double _pitchScale;
    std::vector<float> _inputDeinterleaved;
    std::vector<float> _outputDeinterleaved;
    std::vector<float *> _inputPointers;
    std::vector<float *> _outputPointers;
    std::vector<float> _inputFifo;
    std::vector<float> _outputFifo;
    int _minProcessFrames;
    bool _isPrimed;
}

- (instancetype)initWithSampleRate:(double)sampleRate channels:(int)channels {
    self = [super init];
    if (self) {
        _state = nullptr;
        _channels = channels;
        _sampleRate = sampleRate;
        _pitchScale = 1.0;
        _minProcessFrames = 8192;
        _isPrimed = false;
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

    rubberband_set_max_process_size(_state, 8192);
    _inputFifo.clear();
    _outputFifo.clear();
    _isPrimed = false;
}

- (void)setPitchSemitones:(double)semitones {
    double scale = std::pow(2.0, semitones / 12.0);
    _pitchScale = scale;
    if (_state) {
        rubberband_set_pitch_scale(_state, scale);
    }
}

- (void)setMinimumProcessFrames:(int)frames {
    const int clamped = std::max(256, frames);
    if (_minProcessFrames == clamped) {
        return;
    }
    _minProcessFrames = clamped;
    _isPrimed = false;
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

    const int totalSamples = frames * channels;
    _inputFifo.insert(_inputFifo.end(), input, input + totalSamples);

    const int fifoFrames = (int)(_inputFifo.size() / channels);
    const int processFrames = std::max(_minProcessFrames, frames);
    int consumedFrames = 0;

    while (fifoFrames - consumedFrames >= processFrames) {
        const int chunkFrames = processFrames;
        const int chunkSamples = chunkFrames * channels;
        if ((int)_inputDeinterleaved.size() < chunkSamples) {
            _inputDeinterleaved.resize(chunkSamples);
            _outputDeinterleaved.resize(chunkSamples);
        }

        _inputPointers.assign(channels, nullptr);
        _outputPointers.assign(channels, nullptr);

        for (int ch = 0; ch < channels; ch++) {
            _inputPointers[ch] = _inputDeinterleaved.data() + (size_t)ch * chunkFrames;
            _outputPointers[ch] = _outputDeinterleaved.data() + (size_t)ch * chunkFrames;
        }

        const float *chunk = _inputFifo.data() + (size_t)consumedFrames * channels;
        for (int frame = 0; frame < chunkFrames; frame++) {
            for (int ch = 0; ch < channels; ch++) {
                _inputPointers[ch][frame] = chunk[frame * channels + ch];
            }
        }

        rubberband_set_pitch_scale(_state, _pitchScale);
        rubberband_process(_state, (const float *const *)_inputPointers.data(), (unsigned int)chunkFrames, 0);

        int available = rubberband_available(_state);
        while (available > 0) {
            int toRetrieve = std::min(available, chunkFrames);
            rubberband_retrieve(_state, _outputPointers.data(), (unsigned int)toRetrieve);
            const int retrievedSamples = toRetrieve * channels;
            _outputFifo.reserve(_outputFifo.size() + retrievedSamples);
            for (int frame = 0; frame < toRetrieve; frame++) {
                for (int ch = 0; ch < channels; ch++) {
                    _outputFifo.push_back(_outputPointers[ch][frame]);
                }
            }
            available = rubberband_available(_state);
        }

        consumedFrames += chunkFrames;
    }

    if (consumedFrames > 0) {
        const size_t consumedSamples = (size_t)consumedFrames * channels;
        _inputFifo.erase(_inputFifo.begin(), _inputFifo.begin() + consumedSamples);
    }

    const int availableOutFrames = (int)(_outputFifo.size() / channels);
    const int prebufferFrames = _minProcessFrames * 2;
    if (!_isPrimed) {
        if (availableOutFrames >= prebufferFrames) {
            _isPrimed = true;
        } else {
            const size_t totalOutSamples = (size_t)outputCapacity * channels;
            std::fill(output, output + totalOutSamples, 0.0f);
            return outputCapacity;
        }
    }

    const int toCopyFrames = std::min(outputCapacity, availableOutFrames);

    for (int frame = 0; frame < outputCapacity; frame++) {
        for (int ch = 0; ch < channels; ch++) {
            float value;
            if (frame < toCopyFrames) {
                value = _outputFifo[frame * channels + ch];
            } else {
                value = 0.0f;
            }
            output[frame * channels + ch] = value;
        }
    }

    if (toCopyFrames > 0) {
        const size_t consumedSamples = (size_t)toCopyFrames * channels;
        _outputFifo.erase(_outputFifo.begin(), _outputFifo.begin() + consumedSamples);
    }

    return outputCapacity;
}

- (void)reset {
    if (_state) {
        rubberband_reset(_state);
    }
    _inputFifo.clear();
    _outputFifo.clear();
    _isPrimed = false;
}

@end
