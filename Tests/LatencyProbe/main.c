#include "RealtimeAudioRing.h"
#include <stdio.h>
#include <stdlib.h>

// Deterministic queue experiment, NOT a hardware or scheduler benchmark.
// 48 kHz, stereo, 256-frame callbacks. Producer pauses, then catches up.
int main(void) {
    const unsigned targets[] = {4096, 2048, 1024};
    const unsigned pauses[] = {0, 4, 8, 16};
    float input[16384] = {0}, output[512];
    puts("target_frames,buffer_ms,producer_stall_ms,underflow_frames,dropped_frames");
    for (unsigned t = 0; t < 3; ++t) {
        for (unsigned p = 0; p < 4; ++p) {
            SonexisAudioRingBuffer *ring = SonexisAudioRingBufferCreate(96000, 2);
            if (!ring) return 1;
            SonexisAudioRingBufferSetReadEnabled(ring, true);
            SonexisAudioRingBufferSetTargetFillFrames(ring, targets[t]);
            SonexisAudioRingBufferWriteInterleaved(ring, input, targets[t]);
            for (unsigned tick = 0; tick < 1000; ++tick) {
                unsigned frames = 256;
                if (tick >= 100 && tick < 100 + pauses[p]) frames = 0;
                if (tick == 100 + pauses[p]) frames += pauses[p] * 256;
                if (frames) SonexisAudioRingBufferWriteInterleaved(ring, input, frames);
                SonexisAudioRingBufferReadInterleaved(ring, output, 256);
            }
            printf("%u,%.2f,%.2f,%llu,%llu\n", targets[t], targets[t]/48.0,
                pauses[p]*256/48.0,
                (unsigned long long)SonexisAudioRingBufferGetUnderflowFrames(ring),
                (unsigned long long)SonexisAudioRingBufferGetDroppedFrames(ring));
            SonexisAudioRingBufferDestroy(ring);
        }
    }
    return 0;
}
