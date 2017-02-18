//
//  KFRecorder.h
//  Kickflip
//
//  Created by Christopher Ballinger on 1/16/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "KFAACEncoder.h"
#import "KFH264Encoder.h"
#import <CoreLocation/CoreLocation.h>

#import "kickflip.h"

@class KFRecorder, KFHLSWriter, KFStream;

//@protocol KFRecorderDelegate <NSObject>
//- (void) setFPS:(int)fps;
//- (void) recorderDidStartRecording:(KFRecorder*)recorder error:(NSError*)error;
//- (void) recorderDidFinishRecording:(KFRecorder*)recorder error:(NSError*)error;
//- (void) recorder:(KFRecorder*)recorder streamReadyAtURL:(NSURL*)url;
//@end

/**
 *  KFRecorder manages the majority of the AV pipeline
 */
//@interface KFRecorder : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, KFEncoderDelegate, KFHLSUploaderDelegate, CLLocationManagerDelegate>

@interface KFRecorder : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, KFEncoderDelegate, CLLocationManagerDelegate>

@property (nonatomic, strong) AVCaptureSession* session;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer* previewLayer;
@property (nonatomic, strong) AVCaptureVideoDataOutput* videoOutput;
@property (nonatomic, strong) AVCaptureAudioDataOutput* audioOutput;
@property (nonatomic, strong) dispatch_queue_t videoQueue;
@property (nonatomic, strong) dispatch_queue_t audioQueue;
@property (nonatomic, strong) AVCaptureConnection* audioConnection;
@property (nonatomic, strong) AVCaptureConnection* videoConnection;
@property (nonatomic, strong) CLLocation *lastLocation;

@property (nonatomic, strong) KFAACEncoder *aacEncoder;
@property (nonatomic, strong) KFH264Encoder *h264Encoder;
@property (nonatomic, strong) KFHLSWriter *hlsWriter;
@property (nonatomic, strong) KFStream *stream;

@property (nonatomic) NSUInteger videoWidth;
@property (nonatomic) NSUInteger videoHeight;
@property (nonatomic) NSUInteger audioSampleRate;

@property (nonatomic) BOOL isRecording;

@property (nonatomic, weak) id<KFRecorderDelegate> delegate;

- (id) init;
- (id) initWithBitrateSize:(int)videoBirate
                     withSize:(CGSize)videoSize
          withAudioSampleRate:(NSUInteger)audioSampleRate;

- (void) startRecording:(NSString*)hlsPath;
- (void) stopRecording;

-(BOOL)inputAudioFrame:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio;

-(BOOL)intputVidoFrame:(CMSampleBufferRef)videoSample;

-(BOOL)intputPixelBufferRef:(CVPixelBufferRef)pixelbufferRef;


@end



