//
//  KFRecorder.m
//  FFmpegEncoder
//
//  Created by Christopher Ballinger on 1/16/14.
//  Copyright (c) 2014 Christopher Ballinger. All rights reserved.
//

#import "KFRecorder.h"
#import "KFAACEncoder.h"
#import "KFH264Encoder.h"
//#import "KFHLSMonitor.h"
#import "KFH264Encoder.h"
#import "KFHLSWriter.h"
#import "KFLog.h"
//#import "KFAPIClient.h"
//#import "KFS3Stream.h"
#import "KFFrame.h"
#import "KFVideoFrame.h"
//#import "Kickflip.h"
#import "Endian.h"

#include "../Utilities/mediaProcess.h"


#define   __ENABLE_SDK_CAPTURE_AUIDO_VIDEO__ 1

#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) \
([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)

#define VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE 25

#include <chrono>
#include <iostream>
#include <sys/time.h>

static int64_t systemTimeNs() {
    struct timeval t;
    t.tv_sec = t.tv_usec = 0;
    
    gettimeofday(&t, NULL);
    return t.tv_sec * 1000000000LL + t.tv_usec * 1000LL;
}

static int64_t GetNowMs()
{
    return systemTimeNs() / 1000000ll;
}

static int64_t GetNowUs() {
    return systemTimeNs() / 1000ll;
}

@interface KFRecorder()
@property (nonatomic) double minBitrate;
@property (nonatomic) BOOL hasScreenshot;
@property (nonatomic, strong) CLLocationManager *locationManager;
@end

@implementation KFRecorder{
    AudioComponentInstance m_audioUnit;
    AudioComponent         m_component;
    
    double m_sampleRate;
    int m_channelCount;
    AudioStreamBasicDescription desc;
    int mFps;
    void*                       mAudioPool;
}


//- (void) setupEncoders:(int)videoBitrate withSize:(CGSize)videoSize withAudio:(int) audioBitrate withAudioSampleRate:(NSUInteger)audioSampleRate

- (id) init {
    if (self = [super init]) {
        _minBitrate = 300 * 1000;
        [self setupSession];
        [self setupEncoders];
    }
    
    bool bRet = ::createAudioPool(&mAudioPool, 2048, 20);
    return self;
}

- (id) initWithBitrateSize:(int)videoBirate
                     withSize:(CGSize)videoSize
          withAudioSampleRate:(NSUInteger)audioSampleRate{
    if (self = [super init]) {
        [self setupSession];
        [self setupEncoders:videoBirate withSize:videoSize
            withAudioSampleRate:audioSampleRate];
    }
    
    bool bRet = ::createAudioPool(&mAudioPool, 2048, 20);
    return self;
}

-(BOOL)intputVidoFrame:(CMSampleBufferRef)videoSample
{
    if (!_isRecording) {
        return false;
    }
    
    CMSampleBufferRef sampleBuf = [self adjustTime:videoSample withUs:GetNowUs()];
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuf);
    
    [_h264Encoder encodeSampleBuffer:sampleBuf];
    
    CFRelease(sampleBuf);
    
    return true;
}

-(BOOL)inputAudioFrame:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio
{
    if (!_isRecording) {
        return false;
    }
    
    CMSampleBufferRef buff = NULL;
    CMFormatDescriptionRef format = NULL;
    OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &format);
    if (status) {
        return false;
    }
    
    int64_t timeVale = GetNowUs();
    CMSampleTimingInfo timing = { CMTimeMake(1, asbd.mSampleRate), kCMTimeZero, kCMTimeInvalid };
    
    status = CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, format, (CMItemCount)1024, 1, &timing, 0, NULL, &buff);
    if (status) { //失败
        return status;
    }
    
    ::pushAudioFrame(mAudioPool, (uint8_t*)audio->mBuffers[0].mData, audio->mBuffers[0].mDataByteSize);
        
    unsigned char * pData = NULL;
    int frameSize = 0;
    bool bRet =::getAudioFrameBegin(mAudioPool, &pData, &frameSize);
    if(bRet == false){
        return false;
    }
    
    audio->mBuffers[0].mData = pData;
    audio->mBuffers[0].mDataByteSize = frameSize;
    
    //NSLog(@"buffers.mBuffers[0].mDataByteSize:%d",buffers.mBuffers[0].mDataByteSize);
    status = CMSampleBufferSetDataBufferFromAudioBufferList(buff, kCFAllocatorDefault, kCFAllocatorDefault, 0, audio);
    if (!status) {
        [self inputCallback:buff];
    }
    ::getAudioFrameEnd(mAudioPool);

    return true;
}

- (void) setupHLSWriterWithEndpoint:(NSString *)streamID {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString *folderName = [NSString stringWithFormat:@"%@.hls", streamID];
    NSString *hlsDirectoryPath = [basePath stringByAppendingPathComponent:folderName];
    [[NSFileManager defaultManager] createDirectoryAtPath:hlsDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    self.hlsWriter = [[KFHLSWriter alloc] initWithDirectoryPath:hlsDirectoryPath];
    [_hlsWriter addVideoStreamWithWidth:self.videoWidth height:self.videoHeight];
    [_hlsWriter addAudioStreamWithSampleRate:self.audioSampleRate];

}

- (void) setupEncoders{
    self.audioSampleRate = 44100;
    self.videoHeight = 720;
    self.videoWidth = 1280;
    
    int audioBitrate = 64 * 1000; // 64 Kbps
    int maxBitrate = 2000000;//[Kickflip maxBitrate];
    int videoBitrate = maxBitrate - audioBitrate;
    _h264Encoder = [[KFH264Encoder alloc] initWithBitrate:videoBitrate width:self.videoWidth height:self.videoHeight];
    _h264Encoder.delegate = self;
    
    _aacEncoder = [[KFAACEncoder alloc] initWithBitrate:audioBitrate sampleRate:self.audioSampleRate channels:1];
    _aacEncoder.delegate = self;
    _aacEncoder.addADTSHeader = YES;
}

- (void) setupEncoders:(int)videoBitrate withSize:(CGSize)videoSize  withAudioSampleRate:(NSUInteger)audioSampleRate {
//    self.audioSampleRate = 44100;
//    self.videoHeight = 720;
//    self.videoWidth = 1280;
    
    self.videoHeight = videoSize.height;
    self.videoWidth = videoSize.width;
    
    int audioBitrate = 64 * 1000; // 64 Kbps
    //int maxBitrate = bitrate;//[Kickflip maxBitrate];
    //int videoBitrate = maxBitrate - audioBitrate;
    _h264Encoder = [[KFH264Encoder alloc] initWithBitrate:videoBitrate width:self.videoWidth height:self.videoHeight];
    _h264Encoder.delegate = self;
    
    _aacEncoder = [[KFAACEncoder alloc] initWithBitrate:audioBitrate sampleRate:self.audioSampleRate channels:1];
    _aacEncoder.delegate = self;
    _aacEncoder.addADTSHeader = YES;
}


//调整媒体数据的时间
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample withUs:(int64_t)timeUs
{
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo* pInfo = (CMSampleTimingInfo*)malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].decodeTimeStamp =  CMTimeMake(timeUs, 1000000000);///CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeMake(timeUs, 1000000000);//CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    return sout;
}


#pragma mark KFEncoderDelegate method
- (void) encoder:(KFEncoder*)encoder encodedFrame:(KFFrame *)frame {
    if (encoder == _h264Encoder) {
        KFVideoFrame *videoFrame = (KFVideoFrame*)frame;
        [_hlsWriter processEncodedData:videoFrame.data presentationTimestamp:videoFrame.pts streamIndex:0 isKeyFrame:videoFrame.isKeyFrame];
    } else if (encoder == _aacEncoder) {
        [_hlsWriter processEncodedData:frame.data presentationTimestamp:frame.pts streamIndex:1 isKeyFrame:NO];
    }
}


- (void) startRecording:(NSString *)hlsPath {
    [self setupHLSWriterWithEndpoint:hlsPath];
    
    NSError *error = nil;
    [_hlsWriter prepareForWriting:&error];
    if (error) {
        DDLogError(@"Error preparing for writing: %@", error);
    }
    self.isRecording = YES;
    //if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:error:)]) {
    if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            //[self.delegate recorderDidStartRecording:self error:nil];
            [self.delegate recorderDidStartRecording:nil];
        });
    }
}


- (void) stopRecording {
#ifdef __ENABLE_SDK_CAPTURE_AUIDO_VIDEO__
    AudioOutputUnitStop(m_audioUnit);
#endif
    
    [self.locationManager stopUpdatingLocation];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.lastLocation) {

        }
        [_session stopRunning];
        self.isRecording = NO;
        NSError *error = nil;
        [_hlsWriter finishWriting:&error];
        if (error) {
            DDLogError(@"Error stop recording: %@", error);
        }

        if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidFinishRecording:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                //[self.delegate recorderDidFinishRecording:self error:error];
                [self.delegate recorderDidFinishRecording:error];
            });
        }
    });
}


-(void) inputCallback:(CMSampleBufferRef)sampleBuffer
{
    if (!_isRecording) {
        return;
    }
    
    CMSampleBufferRef sampleBuf = [self adjustTime:sampleBuffer withUs:GetNowUs()];
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuf);
    
    [_aacEncoder encodeSampleBuffer:sampleBuf];
    
    CFRelease(sampleBuf);
}

#ifdef __ENABLE_SDK_CAPTURE_AUIDO_VIDEO__


- (AVCaptureDevice *)audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
        return [devices objectAtIndex:0];
    
    return nil;
}

- (void) setupAudioCapture {
    
    // create capture device with video input
    
    /*
     * Create audio connection
     */
    AVCaptureDevice *audioDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    NSError *error = nil;
    AVCaptureDeviceInput *audioInput = [[AVCaptureDeviceInput alloc] initWithDevice:audioDevice error:&error];
    if (error) {
        NSLog(@"Error getting audio input device: %@", error.description);
    }
    if ([_session canAddInput:audioInput]) {
        [_session addInput:audioInput];
    }
    
    _audioQueue = dispatch_queue_create("Audio Capture Queue", DISPATCH_QUEUE_SERIAL);
    _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
    [_audioOutput setSampleBufferDelegate:self queue:_audioQueue];
    if ([_session canAddOutput:_audioOutput]) {
        [_session addOutput:_audioOutput];
    }
    _audioConnection = [_audioOutput connectionWithMediaType:AVMediaTypeAudio];
}

//add by tzx

- (AVFrameRateRange*)frameRateRangeForFrameRate:(double)frameRate andINPUT:(AVCaptureDeviceInput*) videoInput{
    for (AVFrameRateRange* range in
         videoInput.device.activeFormat.videoSupportedFrameRateRanges)
    {
        if (range.minFrameRate <= frameRate && frameRate <= range.maxFrameRate)
        {
            return range;
        }
    }
    return nil;
}


// Yes this "lockConfiguration" is somewhat silly but we're now setting
// the frame rate in initCapture *before* startRunning is called to
// avoid contention, and we already have a config lock at that point.
- (void)setActiveFrameRateImpl:(double)frameRate  andLocnfig:(BOOL) lockConfiguration  andINPUT:(AVCaptureDeviceInput*) videoInput
{
    
    //    if (!_videoOutput || !_videoInput) {
    //        return;
    //    }
    
    AVFrameRateRange* frameRateRange =
    [self frameRateRangeForFrameRate:frameRate andINPUT:videoInput];
    if (nil == frameRateRange) {
        NSLog(@"unsupported frameRate %f", frameRate);
        return;
    }
    CMTime desiredMinFrameDuration = CMTimeMake(1, frameRate);
    CMTime desiredMaxFrameDuration = CMTimeMake(1, frameRate); // iOS 8 fix
    /*frameRateRange.maxFrameDuration*/;
    
    if(lockConfiguration) [_session beginConfiguration];
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        NSError* error;
        if ([videoInput.device lockForConfiguration:&error]) {
            [videoInput.device
             setActiveVideoMinFrameDuration:desiredMinFrameDuration];
            [videoInput.device
             setActiveVideoMaxFrameDuration:desiredMaxFrameDuration];
            [videoInput.device unlockForConfiguration];
        } else {
            NSLog(@"%@", error);
        }
    } else {
        AVCaptureConnection *conn =
        [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
        if (conn.supportsVideoMinFrameDuration)
            conn.videoMinFrameDuration = desiredMinFrameDuration;
        if (conn.supportsVideoMaxFrameDuration)
            conn.videoMaxFrameDuration = desiredMaxFrameDuration;
    }
    if(lockConfiguration) [_session commitConfiguration];
}
//end by

- (void) setupVideoCapture {
    NSError *error = nil;
    AVCaptureDevice* videoDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    AVCaptureDeviceInput* videoInput = [AVCaptureDeviceInput deviceInputWithDevice:videoDevice error:&error];
    if (error) {
        NSLog(@"Error getting video input device: %@", error.description);
    }
    if ([_session canAddInput:videoInput]) {
        [_session addInput:videoInput];
    }
    
    // create an output for YUV output with self as delegate
    _videoQueue = dispatch_queue_create("Video Capture Queue", DISPATCH_QUEUE_SERIAL);
    _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    [_videoOutput setSampleBufferDelegate:self queue:_videoQueue];
    NSDictionary *captureSettings = @{(NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA)};
    _videoOutput.videoSettings = captureSettings;
    _videoOutput.alwaysDiscardsLateVideoFrames = YES;
    if ([_session canAddOutput:_videoOutput]) {
        [_session addOutput:_videoOutput];
        
        [self setActiveFrameRateImpl:VIDEO_CAPTURE_IOS_DEFAULT_INITIAL_FRAMERATE andLocnfig:(BOOL)FALSE andINPUT:videoInput];//add by tzx
    }
    _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
}

#pragma mark AVCaptureOutputDelegate method
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (!_isRecording) {
        return;
    }
    
    
    int64_t timeVale = GetNowUs();
    CMSampleBufferRef sampleBuf = [self adjustTime:sampleBuffer withUs:timeVale];
    
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuf);
    NSLog(@" pts:%lld\n", pts.value);
    
    // pass frame to encoders
    if (connection == _videoConnection) {
        if (!_hasScreenshot) {
            UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
            NSString *path = [self.hlsWriter.directoryPath stringByAppendingPathComponent:@"thumb.jpg"];
            NSData *imageData = UIImageJPEGRepresentation(image, 0.7);
            [imageData writeToFile:path atomically:NO];
            _hasScreenshot = YES;
        }
        
        
        [_h264Encoder encodeSampleBuffer:sampleBuf];
        
    } else if (connection == _audioConnection) {
        [_aacEncoder encodeSampleBuffer:sampleBuf];
    }
    CFRelease(sampleBuf);
}

// Create a UIImage from sample buffer data
- (UIImage *) imageFromSampleBuffer:(CMSampleBufferRef) sampleBuffer
{
    // Get a CMSampleBuffer's Core Video image buffer for the media data
    CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    // Lock the base address of the pixel buffer
    CVPixelBufferLockBaseAddress(imageBuffer, 0);
    
    // Get the number of bytes per row for the pixel buffer
    void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
    
    // Get the number of bytes per row for the pixel buffer
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
    // Get the pixel buffer width and height
    size_t width = CVPixelBufferGetWidth(imageBuffer);
    size_t height = CVPixelBufferGetHeight(imageBuffer);
    
    // Create a device-dependent RGB color space
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    
    // Create a bitmap graphics context with the sample buffer data
    CGContextRef context = CGBitmapContextCreate(baseAddress, width, height, 8,
                                                 bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    // Create a Quartz image from the pixel data in the bitmap graphics context
    CGImageRef quartzImage = CGBitmapContextCreateImage(context);
    // Unlock the pixel buffer
    CVPixelBufferUnlockBaseAddress(imageBuffer,0);
    
    // Free up the context and color space
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    // Create an image object from the Quartz image
    UIImage *image = [UIImage imageWithCGImage:quartzImage];
    
    // Release the Quartz image
    CGImageRelease(quartzImage);
    
    return (image);
}

- (void) setupSession {
    _session = [[AVCaptureSession alloc] init];
    [self setupVideoCapture];
    //[self setupAudioCapture];
    
    [self setupAudio];
    
    // start capture and a preview layer
    [_session startRunning];
    AudioOutputUnitStart(m_audioUnit);
    
    
    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}


//add by tzx
-(void)setupAudio{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    [session setCategory:AVAudioSessionCategoryPlayAndRecord withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | AVAudioSessionCategoryOptionMixWithOthers error:nil];
    //[session setMode:AVAudioSessionModeVideoChat error:nil];
    [session setActive:YES error:nil];
    
    AudioComponentDescription acd;
    acd.componentType = kAudioUnitType_Output;
    acd.componentSubType = kAudioUnitSubType_RemoteIO;
    acd.componentManufacturer = kAudioUnitManufacturer_Apple;
    acd.componentFlags = 0;
    acd.componentFlagsMask = 0;
    
    m_component = AudioComponentFindNext(NULL, &acd);
    
    AudioComponentInstanceNew(m_component, &m_audioUnit);
    
    UInt32 flagOne = 1;
    
    AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flagOne, sizeof(flagOne));
    
    memset(&desc, 0, sizeof(AudioStreamBasicDescription));
    desc.mSampleRate = 44100.0;//m_sampleRate;
    desc.mFormatID = kAudioFormatLinearPCM;
    desc.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked);
    desc.mChannelsPerFrame = 1;//m_channelCount;
    desc.mFramesPerPacket = 1;
    desc.mBitsPerChannel = 16;
    desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
    desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
    
    AURenderCallbackStruct cb;
    cb.inputProcRefCon =  (__bridge void *)(self);
    cb.inputProc = handleInputBuffer;
    AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desc, sizeof(desc));
    AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));
    
    double kPreferredIOBufferDuration = 1024.0/44100.0;
    [session setPreferredIOBufferDuration:kPreferredIOBufferDuration error:nil];
    
    AudioUnitInitialize(m_audioUnit);
    OSStatus ret = AudioOutputUnitStart(m_audioUnit);
    if(ret != noErr) {
        NSLog(@"Failed to start microphone!");
    }
}

static OSStatus handleInputBuffer(void *inRefCon,
                                  AudioUnitRenderActionFlags *ioActionFlags,
                                  const AudioTimeStamp *inTimeStamp,
                                  UInt32 inBusNumber,
                                  UInt32 inNumberFrames,
                                  AudioBufferList *ioData)
{
    KFRecorder  *kfrecoder = (__bridge KFRecorder*)inRefCon;
    if(kfrecoder == Nil){
        return 0;
    }
    
    AudioBuffer buffer;
    buffer.mData = NULL;
    buffer.mDataByteSize = 0;
    buffer.mNumberChannels = 2;
    
    AudioBufferList buffers;
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0] = buffer;
    AudioStreamBasicDescription asbd = kfrecoder->desc;
    
    CMSampleBufferRef buff = NULL;
    CMFormatDescriptionRef format = NULL;
    OSStatus status = CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &asbd, 0, NULL, 0, NULL, NULL, &format);
    if (status) {
        return status;
    }
    
    int64_t timeVale = GetNowUs();
    CMSampleTimingInfo timing = { CMTimeMake(1, 44100), kCMTimeZero, kCMTimeInvalid };
    
    status = CMSampleBufferCreate(kCFAllocatorDefault, NULL, false, NULL, NULL, format, (CMItemCount)1024, 1, &timing, 0, NULL, &buff);
    if (status) { //失败
        return status;
    }
    
    status = AudioUnitRender(kfrecoder->m_audioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &buffers);
    
    if(!status) {
        ::pushAudioFrame(kfrecoder->mAudioPool, (uint8_t*)buffers.mBuffers[0].mData, buffers.mBuffers[0].mDataByteSize);
        
        unsigned char * pData = NULL;
        int frameSize = 0;
        bool bRet =::getAudioFrameBegin(kfrecoder->mAudioPool, &pData, &frameSize);
        if(bRet == false){
            return 0;
        }
        buffers.mBuffers[0].mData = pData;
        buffers.mBuffers[0].mDataByteSize = frameSize;
        
        //NSLog(@"buffers.mBuffers[0].mDataByteSize:%d",buffers.mBuffers[0].mDataByteSize);
        status = CMSampleBufferSetDataBufferFromAudioBufferList(buff, kCFAllocatorDefault, kCFAllocatorDefault, 0, &buffers);
        if (!status) {
            [kfrecoder inputCallback:buff];
        }
        ::getAudioFrameEnd(kfrecoder->mAudioPool);
    }
    return status;
}


//end by tzx
#endif

@end
