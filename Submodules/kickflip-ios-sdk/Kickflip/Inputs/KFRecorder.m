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
#import "KFHLSMonitor.h"
#import "KFH264Encoder.h"
#import "KFHLSWriter.h"
#import "KFLog.h"
#import "KFAPIClient.h"
#import "KFS3Stream.h"
#import "KFFrame.h"
#import "KFVideoFrame.h"
#import "Kickflip.h"
#import "Endian.h"

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
    //InterruptionHandler*   m_interruptionHandler;
}


- (id) init {
    if (self = [super init]) {
        _minBitrate = 300 * 1000;
        [self setupSession];
        [self setupEncoders];
    }
    return self;
}


//@class InterruptionHandler;
//test
KFAACEncoder *g_aacEncoder = nil;



//add by tzx
-(void)setupAudio{
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    //__block MicSource* bThis = this;

            
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
            
//            if(excludeAudioUnit) {
//                excludeAudioUnit(bThis->m_audioUnit);
//            }
            UInt32 flagOne = 1;
            
            AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &flagOne, sizeof(flagOne));
            
            AudioStreamBasicDescription desc = {0};
            desc.mSampleRate = 44100.0;//m_sampleRate;
            desc.mFormatID = kAudioFormatLinearPCM;
            desc.mFormatFlags = (kAudioFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian | kAudioFormatFlagIsPacked);
            desc.mChannelsPerFrame = 1;//m_channelCount;
            desc.mFramesPerPacket = 1;
            desc.mBitsPerChannel = 16;
            desc.mBytesPerFrame = desc.mBitsPerChannel / 8 * desc.mChannelsPerFrame;
            desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;
            
            AURenderCallbackStruct cb;
            cb.inputProcRefCon =  (__bridge void *)(self);   //m_audioUnit;
            cb.inputProc = handleInputBuffer;
            AudioUnitSetProperty(m_audioUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &desc, sizeof(desc));
            AudioUnitSetProperty(m_audioUnit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1, &cb, sizeof(cb));
            
//            m_interruptionHandler = [[InterruptionHandler alloc] init];
//            m_interruptionHandler->_source = m_audioUnit;
    
//            [[NSNotificationCenter defaultCenter] addObserver:m_interruptionHandler selector:@selector(handleInterruption:) name:AVAudioSessionInterruptionNotification object:nil];
    
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
    //AudioComponentInstance audioUnit = inRefCon;
    
    //videocore::iOS::MicSource* mc =static_cast<videocore::iOS::MicSource*>(inRefCon);
    
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
    
    OSStatus status = AudioUnitRender(kfrecoder->m_audioUnit,
                                      ioActionFlags,
                                      inTimeStamp,
                                      inBusNumber,
                                      inNumberFrames,
                                      &buffers);
    
    if(!status) {
        //mc->inputCallback((uint8_t*)buffers.mBuffers[0].mData, buffers.mBuffers[0].mDataByteSize, inNumberFrames);
        
        
        //[g_aacEncoder encodePCMBuffer:buffers];
        [kfrecoder inputCallback:buffers];
    }
    return status;
}


-(void) inputCallback:(AudioBufferList)pcmBuffer
{
    if (!_isRecording) {
        return;
    }
    [_aacEncoder encodePCMBuffer:pcmBuffer];
}

//end by tzx



- (AVCaptureDevice *)audioDevice
{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio];
    if ([devices count] > 0)
        return [devices objectAtIndex:0];
    
    return nil;
}

- (void) setupHLSWriterWithEndpoint:(KFS3Stream*)endpoint {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *basePath = ([paths count] > 0) ? [paths objectAtIndex:0] : nil;
    NSString *folderName = [NSString stringWithFormat:@"%@.hls", endpoint.streamID];
    NSString *hlsDirectoryPath = [basePath stringByAppendingPathComponent:folderName];
    [[NSFileManager defaultManager] createDirectoryAtPath:hlsDirectoryPath withIntermediateDirectories:YES attributes:nil error:nil];
    self.hlsWriter = [[KFHLSWriter alloc] initWithDirectoryPath:hlsDirectoryPath];
    [_hlsWriter addVideoStreamWithWidth:self.videoWidth height:self.videoHeight];
    [_hlsWriter addAudioStreamWithSampleRate:self.audioSampleRate];

}

- (void) setupEncoders {
    self.audioSampleRate = 44100;
    self.videoHeight = 720;
    self.videoWidth = 1280;
    int audioBitrate = 64 * 1000; // 64 Kbps
    int maxBitrate = [Kickflip maxBitrate];
    int videoBitrate = maxBitrate - audioBitrate;
    _h264Encoder = [[KFH264Encoder alloc] initWithBitrate:videoBitrate width:self.videoWidth height:self.videoHeight];
    _h264Encoder.delegate = self;
    
    _aacEncoder = [[KFAACEncoder alloc] initWithBitrate:audioBitrate sampleRate:self.audioSampleRate channels:1];
    _aacEncoder.delegate = self;
    _aacEncoder.addADTSHeader = YES;
    
    g_aacEncoder = _aacEncoder;
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
    }
    _videoConnection = [_videoOutput connectionWithMediaType:AVMediaTypeVideo];
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

#pragma mark AVCaptureOutputDelegate method
- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    if (!_isRecording) {
        return;
    }
    // pass frame to encoders
    if (connection == _videoConnection) {
        if (!_hasScreenshot) {
            UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
            NSString *path = [self.hlsWriter.directoryPath stringByAppendingPathComponent:@"thumb.jpg"];
            NSData *imageData = UIImageJPEGRepresentation(image, 0.7);
            [imageData writeToFile:path atomically:NO];
            _hasScreenshot = YES;
        }
        [_h264Encoder encodeSampleBuffer:sampleBuffer];
    } else if (connection == _audioConnection) {
        [_aacEncoder encodeSampleBuffer:sampleBuffer];
    }
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
   // [self setupAudioCapture];
    
    [self setupAudio];

    // start capture and a preview layer
    [_session startRunning];
    AudioOutputUnitStart(m_audioUnit);


    _previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:_session];
    _previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
}

- (void) startRecording {
#if 1
    
    [self setupHLSWriterWithEndpoint:nil];
    
    [[KFHLSMonitor sharedMonitor] startMonitoringFolderPath:_hlsWriter.directoryPath endpoint:nil delegate:self];
    
    NSError *error = nil;
    [_hlsWriter prepareForWriting:&error];
    if (error) {
        DDLogError(@"Error preparing for writing: %@", error);
    }
    self.isRecording = YES;
    if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:error:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate recorderDidStartRecording:self error:nil];
        });
    }
#else
    
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
    [self.locationManager startUpdatingLocation];
    [[KFAPIClient sharedClient] startNewStream:^(KFStream *endpointResponse, NSError *error) {
//del by tzx
//        if (error) {
//            if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:error:)]) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [self.delegate recorderDidStartRecording:self error:error];
//                });
//            }
//            return;
//        }
        self.stream = endpointResponse;
        [self setStreamStartLocation];
       // if ([endpointResponse isKindOfClass:[KFS3Stream class]]) { //del by tzx
        {
            KFS3Stream *s3Endpoint = (KFS3Stream*)endpointResponse;
            s3Endpoint.streamState = KFStreamStateStreaming;
            [self setupHLSWriterWithEndpoint:s3Endpoint];
            
            [[KFHLSMonitor sharedMonitor] startMonitoringFolderPath:_hlsWriter.directoryPath endpoint:s3Endpoint delegate:self];
            
            NSError *error = nil;
            [_hlsWriter prepareForWriting:&error];
            if (error) {
                DDLogError(@"Error preparing for writing: %@", error);
            }
            self.isRecording = YES;
            if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidStartRecording:error:)]) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self.delegate recorderDidStartRecording:self error:nil];
                });
            }
        }
    }];
#endif
}

- (void) reverseGeocodeStream:(KFStream*)stream {
    CLLocation *location = nil;
    CLLocation *endLocation = stream.endLocation;
    CLLocation *startLocation = stream.startLocation;
    if (startLocation) {
        location = startLocation;
    }
    if (endLocation) {
        location = endLocation;
    }
    if (!location) {
        return;
    }
    CLGeocoder *geocoder = [[CLGeocoder alloc] init];
    [geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        if (error) {
            DDLogError(@"Error geocoding stream: %@", error);
            return;
        }
        if (placemarks.count == 0) {
            return;
        }
        CLPlacemark *placemark = [placemarks firstObject];
        stream.city = placemark.locality;
        stream.state = placemark.administrativeArea;
        stream.country = placemark.country;
        [[KFAPIClient sharedClient] updateMetadataForStream:stream callbackBlock:^(KFStream *updatedStream, NSError *error) {
            if (error) {
                DDLogError(@"Error updating stream geocoder info: %@", error);
            }
        }];
    }];
}

- (void) stopRecording {
    
    AudioOutputUnitStop(m_audioUnit);
    
    [self.locationManager stopUpdatingLocation];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        if (self.lastLocation) {
            self.stream.endLocation = self.lastLocation;
            [[KFAPIClient sharedClient] updateMetadataForStream:self.stream callbackBlock:^(KFStream *updatedStream, NSError *error) {
                if (error) {
                    DDLogError(@"Error updating stream endLocation: %@", error);
                }
            }];
        }
        [_session stopRunning];
        self.isRecording = NO;
        NSError *error = nil;
        [_hlsWriter finishWriting:&error];
        if (error) {
            DDLogError(@"Error stop recording: %@", error);
        }
        //del by tzx
//        [[KFAPIClient sharedClient] stopStream:self.stream callbackBlock:^(BOOL success, NSError *error) {
//            if (!success) {
//                DDLogError(@"Error stopping stream: %@", error);
//            } else {
//                DDLogVerbose(@"Stream stopped: %@", self.stream.streamID);
//            }
//        }];
        if ([self.stream isKindOfClass:[KFS3Stream class]]) {
            [[KFHLSMonitor sharedMonitor] finishUploadingContentsAtFolderPath:_hlsWriter.directoryPath endpoint:(KFS3Stream*)self.stream];
        }
        if (self.delegate && [self.delegate respondsToSelector:@selector(recorderDidFinishRecording:error:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate recorderDidFinishRecording:self error:error];
            });
        }
    });
}

- (void) uploader:(KFHLSUploader *)uploader didUploadSegmentAtURL:(NSURL *)segmentURL uploadSpeed:(double)uploadSpeed numberOfQueuedSegments:(NSUInteger)numberOfQueuedSegments {
    DDLogInfo(@"Uploaded segment %@ @ %f KB/s, numberOfQueuedSegments %d", segmentURL, uploadSpeed, numberOfQueuedSegments);
    if ([Kickflip useAdaptiveBitrate]) {
        double currentUploadBitrate = uploadSpeed * 8 * 1024; // bps
        double maxBitrate = [Kickflip maxBitrate];

        double newBitrate = currentUploadBitrate * 0.5;
        if (newBitrate > maxBitrate) {
            newBitrate = maxBitrate;
        }
        if (newBitrate < _minBitrate) {
            newBitrate = _minBitrate;
        }
        double newVideoBitrate = newBitrate - self.aacEncoder.bitrate;
        self.h264Encoder.bitrate = newVideoBitrate;
    }
}

- (void) uploader:(KFHLSUploader *)uploader liveManifestReadyAtURL:(NSURL *)manifestURL {
    if (self.delegate && [self.delegate respondsToSelector:@selector(recorder:streamReadyAtURL:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate recorder:self streamReadyAtURL:manifestURL];
        });
    }
    DDLogVerbose(@"Manifest ready at URL: %@", manifestURL);
}

- (void) locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    self.lastLocation = [locations lastObject];
    [self setStreamStartLocation];
}

- (void) setStreamStartLocation {
    if (!self.lastLocation) {
        return;
    }
    if (self.stream && !self.stream.startLocation) {
        self.stream.startLocation = self.lastLocation;
        [[KFAPIClient sharedClient] updateMetadataForStream:self.stream callbackBlock:^(KFStream *updatedStream, NSError *error) {
            if (error) {
                DDLogError(@"Error updating stream startLocation: %@", error);
            }
        }];
        [self reverseGeocodeStream:self.stream];
    }
}

@end
