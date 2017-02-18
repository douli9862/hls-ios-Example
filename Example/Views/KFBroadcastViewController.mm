         //
//  KFBroadcastViewController.m
//  Encoder Demo
//
//  Created by Geraint Davies on 11/01/2013.
//  Copyright (c) 2013 GDCL http://www.gdcl.co.uk/license.htm
//

#import <CoreMedia/CMSampleBuffer.h>

#import "KFBroadcastViewController.h"
//#import "KFRecorder.h"
//#import "KFAPIClient.h"
#import "kickflip.h"
//#import "KFUser.h"
#import "KFLog.h"
#import "PureLayout.h"



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



@implementation KFBroadcastViewController
{
    AudioComponentInstance m_audioUnit;
    AudioComponent         m_component;
    
    double m_sampleRate;
    int m_channelCount;
    AudioStreamBasicDescription desc;
    
    KFRecorderNode *recorder;
}



//调整媒体数据的时间
-(CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample withUs:(int64_t)timeUs
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

#if 0
- (id) init {
    if (self = [super init]) {
        self.recorder = [[KFRecorder alloc] init];
        CGSize videoSize;
        videoSize.width = 1280;
        videoSize.height = 720;
        //self.recorder = [[KFRecorder alloc] initWithBitrateSize:2000000 withSize:videoSize withAudioSampleRate:44100];
        self.recorder.delegate = self;
    }
    return self;
}
#else

- (id) init {
    if (self = [super init]) {
        //self.recorder = [[KFRecorder alloc] init];
        //self->recorder = [[KFRecorderNode alloc]init];
        //self->recorder = [[KFRecorderNode alloc]initDelegate:self];
        CGSize videoSize;
        
        [self setupSession];
        videoSize.width = 1280;
        videoSize.height = 720;
        self->recorder = [[KFRecorderNode alloc] initWithBitrateSize:self withVideoBirate:2000000 withSize:videoSize withAudioSampleRate:44100];
        //self.recorder.delegate = self;
    }
    return self;
}

#endif

- (void) setupCameraView {
    _cameraView = [[UIView alloc] init];
    _cameraView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    [self.view addSubview:_cameraView];
}

- (void) setupShareButton {
    _shareButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [_shareButton addTarget:self action:@selector(shareButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [_shareButton setTitle:@"Share" forState:UIControlStateNormal];
    [_shareButton setTitle:@"Buffering..." forState:UIControlStateDisabled];
    self.shareButton.enabled = NO;
    self.shareButton.alpha = 0.0f;
    self.shareButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.shareButton];
    NSLayoutConstraint *constraint = [self.shareButton autoPinEdgeToSuperviewEdge:ALEdgeTop withInset:10.0f];
    [self.view addConstraint:constraint];
    constraint = [self.shareButton autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:10.0f];
    [self.view addConstraint:constraint];
}

- (void) setupRecordButton {
    self.recordButton = [[KFRecordButton alloc] initWithFrame:CGRectZero];
    [self.view addSubview:self.recordButton];
    [self.recordButton addTarget:self action:@selector(recordButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    
    NSLayoutConstraint *constraint = [self.recordButton autoPinEdgeToSuperviewEdge:ALEdgeRight withInset:10.0f];
    [self.view addConstraint:constraint];
    constraint = [self.recordButton autoAlignAxisToSuperviewAxis:ALAxisHorizontal];
    [self.view addConstraint:constraint];
}

- (void) setupCancelButton {
    self.cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    self.cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    [self.cancelButton addTarget:self action:@selector(cancelButtonPressed:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cancelButton];
    
    NSLayoutConstraint *constraint = [self.cancelButton autoPinEdgeToSuperviewEdge:ALEdgeBottom withInset:10.0f];
    [self.view addConstraint:constraint];
    constraint = [self.cancelButton autoPinEdgeToSuperviewEdge:ALEdgeLeft withInset:10.0f];
    [self.view addConstraint:constraint];
}

- (void) setupRotationLabel {
    self.rotationLabel = [[UILabel alloc] init];
    self.rotationLabel.text = @"Rotate Device to Begin";
    self.rotationLabel.textAlignment = NSTextAlignmentCenter;
    self.rotationLabel.font = [UIFont fontWithName:@"HelveticaNeue-Light" size:17.0f];
    self.rotationLabel.textColor = [UIColor whiteColor];
    self.rotationLabel.shadowColor = [UIColor blackColor];
    self.rotationLabel.shadowOffset = CGSizeMake(0, -1);
    self.rotationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.rotationLabel];
    [self.rotationLabel autoPinEdge:ALEdgeTop toEdge:ALEdgeBottom ofView:self.rotationImageView withOffset:10.0f];
    [self.rotationLabel autoAlignAxisToSuperviewAxis:ALAxisVertical];
}

- (void) setupRotationImageView {
    self.rotationImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"KFDeviceRotation"]];
    self.rotationImageView.translatesAutoresizingMaskIntoConstraints = NO;
    self.rotationImageView.transform = CGAffineTransformMakeRotation(90./180.*M_PI);
    [self.view addSubview:self.rotationImageView];
    [self.rotationImageView autoCenterInSuperview];
}

- (void) cancelButtonPressed:(id)sender {
    if (_completionBlock) {
        _completionBlock(YES, nil);
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}


bool isRecording = false;

- (void) recordButtonPressed:(id)sender {
    self.recordButton.enabled = NO;
    self.cancelButton.enabled = NO;
    [UIView animateWithDuration:0.2 animations:^{
        self.cancelButton.alpha = 0.0f;
    }];
#if 0
    if (!self.recorder.isRecording) {
        [self.recorder startRecording:@"hls-out"];
    } else {
        [self.recorder stopRecording];
    }
#else
    if (!isRecording) {
        [self->recorder startSession:@"hls-out"];
        isRecording = true;
    } else {
        isRecording = false;
        AudioOutputUnitStop(m_audioUnit);
        [self->recorder endSession];
    }
#endif
}

- (void) shareButtonPressed:(id)sender {
//    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[self.recorder.stream.kickflipURL] applicationActivities:nil];
    
       UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:nil applicationActivities:nil];
    
    UIActivityViewControllerCompletionHandler completionHandler = ^(NSString *activityType, BOOL completed) {
        NSLog(@"share activity: %@", activityType);
    };
    activityViewController.completionHandler = completionHandler;
    
    [self presentViewController:activityViewController animated:YES completion:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupCameraView];
    [self setupShareButton];
    [self setupRecordButton];
    [self setupCancelButton];
    [self setupRotationImageView];
    [self setupRotationLabel];
}

- (void) viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:NO withAnimation:UIStatusBarAnimationFade];
}

- (void) viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationFade];
    
    _cameraView.frame = self.view.bounds;
    
    [self checkViewOrientation:animated];
    
    [self startPreview];
}


#if 0
- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // this is not the most beautiful animation...
    AVCaptureVideoPreviewLayer* preview = self.recorder.previewLayer;
    [UIView animateWithDuration:duration animations:^{
        preview.frame = self.cameraView.bounds;
    } completion:NULL];
    [[preview connection] setVideoOrientation:[self avOrientationForInterfaceOrientation:toInterfaceOrientation]];
    
    [self checkViewOrientation:YES];
}

#else
- (void) willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration
{
    // this is not the most beautiful animation...
    AVCaptureVideoPreviewLayer* preview = self.previewLayer;
    [UIView animateWithDuration:duration animations:^{
        preview.frame = self.cameraView.bounds;
    } completion:NULL];
    [[preview connection] setVideoOrientation:[self avOrientationForInterfaceOrientation:toInterfaceOrientation]];
    
    [self checkViewOrientation:YES];
}

#endif


- (void) checkViewOrientation:(BOOL)animated {
    CGFloat duration = 0.2f;
    if (!animated) {
        duration = 0.0f;
    }
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    // Hide controls in Portrait
    if (orientation == UIInterfaceOrientationPortrait || orientation == UIInterfaceOrientationPortrait) {
        self.recordButton.enabled = NO;
        [UIView animateWithDuration:0.2 animations:^{
            self.shareButton.alpha = 0.0f;
            self.recordButton.alpha = 0.0f;
            self.rotationLabel.alpha = 1.0f;
            self.rotationImageView.alpha = 1.0f;
        } completion:NULL];
    } else {
        self.recordButton.enabled = YES;
        [UIView animateWithDuration:0.2 animations:^{
            //if (self.recorder.isRecording) {
            if(isRecording){
                self.shareButton.alpha = 1.0f;
            }
            self.recordButton.alpha = 1.0f;
            self.rotationLabel.alpha = 0.0f;
            self.rotationImageView.alpha = 0.0f;
        } completion:NULL];
    }
}

- (AVCaptureVideoOrientation) avOrientationForInterfaceOrientation:(UIInterfaceOrientation)orientation {
    switch (orientation) {
        case UIInterfaceOrientationPortrait:
            return AVCaptureVideoOrientationPortrait;
            break;
        case UIInterfaceOrientationPortraitUpsideDown:
            return AVCaptureVideoOrientationPortraitUpsideDown;
            break;
        case UIInterfaceOrientationLandscapeLeft:
            return AVCaptureVideoOrientationLandscapeLeft;
            break;
        case UIInterfaceOrientationLandscapeRight:
            return AVCaptureVideoOrientationLandscapeRight;
            break;
        default:
            return AVCaptureVideoOrientationLandscapeLeft;
            break;
    }
}

- (void) startPreview
{
    AVCaptureVideoPreviewLayer* preview = self.previewLayer;
    [preview removeFromSuperlayer];
    preview.frame = self.cameraView.bounds;
    
    UIInterfaceOrientation orientation = [UIApplication sharedApplication].statusBarOrientation;
    
    [[preview connection] setVideoOrientation:[self avOrientationForInterfaceOrientation:orientation]];
    
    [self.cameraView.layer addSublayer:preview];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

//- (void) recorderDidStartRecording:(KFRecorder *)recorder error:(NSError *)error {
- (void) recorderDidStartRecording:(NSError *)error {
    self.recordButton.enabled = YES;
    if (error) {
        DDLogError(@"Error starting stream: %@", error.userInfo);
        NSDictionary *response = [error.userInfo objectForKey:@"response"];
        NSString *reason = nil;
        if (response) {
            reason = [response objectForKey:@"reason"];
        }
        NSMutableString *errorMsg = [NSMutableString stringWithFormat:@"Error starting stream: %@.", error.localizedDescription];
        if (reason) {
            [errorMsg appendFormat:@" %@", reason];
        }
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Stream Start Error" message:errorMsg delegate:nil cancelButtonTitle:nil otherButtonTitles:@"OK", nil];
        [alertView show];
        self.recordButton.isRecording = NO;
    } else {
        self.recordButton.isRecording = YES;
        self.shareButton.alpha = 1.0f;
    }
}

- (void) recorder:(KFRecorder *)recorder streamReadyAtURL:(NSURL *)url {
    self.shareButton.enabled = YES;
    if (_readyBlock) {
        //_readyBlock(recorder.stream);
    }
}

//- (void) recorderDidFinishRecording:(KFRecorder *)recorder error:(NSError *)error {
- (void) recorderDidFinishRecording:(NSError *)error {
    if (_completionBlock) {
        if (error) {
            _completionBlock(NO, error);
        } else {
            _completionBlock(YES, nil);
        }
    }
    [self dismissViewControllerAnimated:YES completion:nil];
}



#if 1

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
    
    //- (void)setSampleBufferDelegate:(id<AVCaptureAudioDataOutputSampleBufferDelegate>)sampleBufferDelegate queue:(dispatch_queue_t)sampleBufferCallbackQueue;
    
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
    if (!isRecording) {
        return;
    }
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    
    
//    int64_t timeVale = GetNowUs();
//    CMSampleBufferRef sampleBuf = [self adjustTime:sampleBuffer withUs:timeVale];
//    
//    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuf);
//    NSLog(@" pts:%lld\n", pts.value);
    
    // pass frame to encoders
    if (connection == _videoConnection) {
//        if (!_hasScreenshot) {
//            UIImage *image = [self imageFromSampleBuffer:sampleBuffer];
//            NSString *path = [self.hlsWriter.directoryPath stringByAppendingPathComponent:@"thumb.jpg"];
//            NSData *imageData = UIImageJPEGRepresentation(image, 0.7);
//            [imageData writeToFile:path atomically:NO];
//            _hasScreenshot = YES;
//        }
//        
        
        //[_h264Encoder encodeSampleBuffer:sampleBuf];
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        
        //[self->recorder encodeVideoWithSample:sampleBuf];
        
        [self->recorder encodeVideoWithPixelBuffer:imageBuffer time:pts];
        
//        [self->recorder encodeAudioWithASBD:<#(AudioStreamBasicDescription)#> time:<#(const AudioTimeStamp *)#> numberOfFrames:<#(UInt32)#> buffer:<#(AudioBufferList *)#>];
        
    } else if (connection == _audioConnection) {
       // [_aacEncoder encodeSampleBuffer:sampleBuf];
    }
    //CFRelease(sampleBuf);
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
    KFBroadcastViewController  *pSelf = (__bridge KFBroadcastViewController*)inRefCon;
    if(pSelf == Nil){
        return 0;
    }
    
    AudioBuffer buffer;
    buffer.mData = NULL;
    buffer.mDataByteSize = 0;
    buffer.mNumberChannels = 2;
    
    AudioBufferList buffers;
    buffers.mNumberBuffers = 1;
    buffers.mBuffers[0] = buffer;
    AudioStreamBasicDescription asbd = pSelf->desc;
    
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
    
    status = AudioUnitRender(pSelf->m_audioUnit,
                             ioActionFlags,
                             inTimeStamp,
                             inBusNumber,
                             inNumberFrames,
                             &buffers);
    
    if(!status) {
        
        //AudioTimeStamp times;
        //- (void)encodeAudioWithASBD:(AudioStreamBasicDescription)asbd time:(const AudioTimeStamp *)time numberOfFrames:(UInt32)frames buffer:(AudioBufferList *)audio;
        
        //- (void)encodeAudioWithASBDEX:(AudioStreamBasicDescription)asbd buffer:(AudioBufferList *)audio

        KFRecorderNode *recorder_ =  pSelf->recorder;
        if(recorder_){
        
        [pSelf->recorder encodeAudioWithASBDEX:asbd buffer:(AudioBufferList*)&buffers];
        
        [pSelf->recorder encodeAudioWithASBD:asbd time:inTimeStamp numberOfFrames:inBusNumber buffer:(AudioBufferList*)&buffers];
        }
//        ::pushAudioFrame(kfrecoder->mAudioPool, (uint8_t*)buffers.mBuffers[0].mData, buffers.mBuffers[0].mDataByteSize);
//        
//        unsigned char * pData = NULL;
//        int frameSize = 0;
//        bool bRet =::getAudioFrameBegin(kfrecoder->mAudioPool, &pData, &frameSize);
//        if(bRet == false){
//            return 0;
//        }
//        buffers.mBuffers[0].mData = pData;
//        buffers.mBuffers[0].mDataByteSize = frameSize;
//        
//        //NSLog(@"buffers.mBuffers[0].mDataByteSize:%d",buffers.mBuffers[0].mDataByteSize);
//        status = CMSampleBufferSetDataBufferFromAudioBufferList(buff, kCFAllocatorDefault, kCFAllocatorDefault, 0, &buffers);
//        if (!status) {
//            [kfrecoder inputCallback:buff];
//        }
//        ::getAudioFrameEnd(kfrecoder->mAudioPool);
    }
    return status;
}


//end by tzx
#endif



@end
