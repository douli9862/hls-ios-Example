//
//  Kickflip.m
//  FFmpegEncoder
//
//  Created by Christopher Ballinger on 1/16/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "Kickflip.h"
//#import "KFLog.h"
//#import "KFBroadcastViewController.h"
#import "KFRecorder.h"

@interface KFRecorderNode()
//@property (nonatomic, copy) NSString *apiKey;
//@property (nonatomic, copy) NSString *apiSecret;
@property (nonatomic) NSUInteger maxBitrate;
@property (nonatomic) BOOL useAdaptiveBitrate;
@end

//static Kickflip *_kickflip = nil;
//
@implementation KFRecorderNode
{
    KFRecorder *_recorderSession;
}


- (id) initDelegate:(id<KFRecorderDelegate>)delegate
{
    _recorderSession = [[KFRecorder alloc] init];
    _recorderSession.delegate = delegate;
}

- (id) initWithBitrateSize:(id<KFRecorderDelegate>)delegate withVideoBirate:(int)videoBirate
                  withSize:(CGSize)videoSize
       withAudioSampleRate:(NSUInteger)audioSampleRate
{
    _recorderSession = [[KFRecorder alloc] initWithBitrateSize:videoBirate withSize:videoSize withAudioSampleRate:audioSampleRate];
    _recorderSession.delegate = delegate;
    
    
}

- (void)startSession:(NSString*)hlsPath
{
    if(_recorderSession){
        [_recorderSession startRecording:hlsPath];
    }
}

- (void)encodeAudioWithASBD:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio
{
    if(_recorderSession){
        [_recorderSession inputAudioFrame:asbd time:time numberOfFrames:frames buffer:audio];
    }
}

- (void)encodeVideoWithPixelBuffer:(CVPixelBufferRef)buffer time:(CMTime)time
{

}

- (void)encodeVideoWithSample:(CMSampleBufferRef)sample
{
    if(_recorderSession){
        [_recorderSession intputVidoFrame:sample];
    }
}

- (void)endSession{
    if(_recorderSession){
        [_recorderSession stopRecording];
    }
}


@end
