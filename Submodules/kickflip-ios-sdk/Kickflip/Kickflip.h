//
//  Kickflip.h
//  FFmpegEncoder
//
//  Created by Christopher Ballinger on 1/16/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


#import <CoreAudio/CoreAudioTypes.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CMSampleBuffer.h>
#import <CoreMedia/CMTime.h>

@protocol KFRecorderDelegate <NSObject> 
- (void) recorderDidStartRecording:(NSError*)error;
- (void) recorderDidFinishRecording:(NSError*)error;
@end


//@interface KFRecorderNode : NSObject  <KFRecorderDelegate>
@interface KFRecorderNode : NSObject  <KFRecorderDelegate>
@property (nonatomic, assign) CGSize exportSize;
@property (nonatomic, strong) NSString *hlsPath;


- (id) init;

- (id) initDelegate:(id<KFRecorderDelegate>)delegate;

//initWithBitrateSize
- (id) initWithBitrateSize:(id<KFRecorderDelegate>)delegate withVideoBirate:(int)videoBirate
                  withSize:(CGSize)videoSize
       withAudioSampleRate:(NSUInteger)audioSampleRate;

- (void)startSession:(NSString*)hlsPath;

- (void)encodeAudioWithASBDEX:(AudioStreamBasicDescription)asbd buffer:(AudioBufferList *)audio;

//- (void)encodeAudioWithASBD:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio;
- (void)encodeAudioWithASBD:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio;

- (void)encodeVideoWithPixelBuffer:(CVPixelBufferRef)buffer time:(CMTime)time;

- (void)encodeVideoWithSample:(CMSampleBufferRef)sample;
- (void)endSession;

@end
