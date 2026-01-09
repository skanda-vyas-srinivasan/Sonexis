#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface RubberBandWrapper : NSObject

- (instancetype)initWithSampleRate:(double)sampleRate channels:(int)channels;
- (void)configureWithSampleRate:(double)sampleRate channels:(int)channels;
- (void)setPitchSemitones:(double)semitones;
- (void)setMinimumProcessFrames:(int)frames;
- (int)processInput:(const float *)input
             frames:(int)frames
           channels:(int)channels
             output:(float *)output
    outputCapacity:(int)outputCapacity;
- (void)reset;

@end

NS_ASSUME_NONNULL_END
