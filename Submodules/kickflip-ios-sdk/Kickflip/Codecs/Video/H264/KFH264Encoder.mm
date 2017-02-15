//
//  KFH264Encoder.m
//  Kickflip
//
//  Created by Christopher Ballinger on 2/11/14.
//  Copyright (c) 2014 Kickflip. All rights reserved.
//

#import "KFH264Encoder.h"
#import "AVEncoder.h"
#import "NALUnit.h"
#import "KFLog.h"
#import "KFVideoFrame.h"

#include <chrono>
#include <iostream>
#include <sys/time.h>
#include <thread>
#include <mutex>

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

@interface KFH264Encoder()
@property (nonatomic, strong) AVEncoder* encoder;
@property (nonatomic, strong) NSData *naluStartCode;
@property (nonatomic, strong) NSMutableData *videoSPSandPPS;
@property (nonatomic) CMTimeScale timescale;
@property (nonatomic, strong) NSMutableArray *orphanedFrames;
@property (nonatomic, strong) NSMutableArray *orphanedSEIFrames;
@property (nonatomic) CMTime lastPTS;
@end

@implementation KFH264Encoder
{
    std::chrono::steady_clock::time_point m_epoch;
    std::chrono::steady_clock::time_point m_nextMixTime;
    std::chrono::steady_clock::time_point m_lastMixTime;
    double m_frameDuration;
    double m_bufferDuration;
    std::thread m_mixThread;
    
    std::mutex  m_mixMutex;
    std::condition_variable m_mixThreadCond;
    
    std::atomic<bool> m_exiting;


}

- (void) dealloc {
    [_encoder shutdown];
    
    m_exiting = true;
    m_mixThreadCond.notify_all();
    if(m_mixThread.joinable()) {
        m_mixThread.join();
    }
}

-(void)start
{
    m_mixThread = std::thread([self]() {
        pthread_setname_np("com.videocore.audiomixer");
        [self mixThread];
    });
}

-(void)mixThread
{
    const auto us = std::chrono::microseconds(static_cast<long long>(m_frameDuration * 1000000.)) ;
    
    const auto start = m_epoch;

    NSLog(@"Exiting audio mixer...\n");
}

/*! ITransform::setEpoch */
-(void) setEpoch:(const std::chrono::steady_clock::time_point) epoch {
    m_epoch = epoch;
    m_nextMixTime = epoch;
};

- (instancetype) initWithBitrate:(NSUInteger)bitrate width:(int)width height:(int)height {
    if (self = [super initWithBitrate:bitrate]) {
        [self initializeNALUnitStartCode];
        _lastPTS = kCMTimeInvalid;
        _timescale = 0;
        self.orphanedFrames = [NSMutableArray arrayWithCapacity:2];
        self.orphanedSEIFrames = [NSMutableArray arrayWithCapacity:2];
        _encoder = [AVEncoder encoderForHeight:height andWidth:width bitrate:bitrate];
        [_encoder encodeWithBlock:^int(NSArray* dataArray, CMTimeValue ptsValue) {
            [self incomingVideoFrames:dataArray ptsValue:ptsValue];
            return 0;
        } onParams:^int(NSData *data) {
            return 0;
        }];
    }
    return self;
}

- (void) initializeNALUnitStartCode {
    NSUInteger naluLength = 4;
    uint8_t *nalu = (uint8_t*)malloc(naluLength * sizeof(uint8_t));
    nalu[0] = 0x00;
    nalu[1] = 0x00;
    nalu[2] = 0x00;
    nalu[3] = 0x01;
    _naluStartCode = [NSData dataWithBytesNoCopy:nalu length:naluLength freeWhenDone:YES];
}

- (void) setBitrate:(NSUInteger)bitrate {
    [super setBitrate:bitrate];
    _encoder.bitrate = self.bitrate;
}

- (void) encodeSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    //NSLog(@"set Output end outPts:%lld, pts:%lld\n", outPts.value, pts.value);

    if (!_timescale) {
        _timescale = pts.timescale;
    }
    [_encoder encodeFrame:sampleBuffer];
}

- (void) generateSPSandPPS {
    NSData* config = _encoder.getConfigData;
    if (!config) {
        return;
    }
    avcCHeader avcC((const BYTE*)[config bytes], [config length]);
    SeqParamSet seqParams;
    seqParams.Parse(avcC.sps());
    
    NSData* spsData = [NSData dataWithBytes:avcC.sps()->Start() length:avcC.sps()->Length()];
    NSData *ppsData = [NSData dataWithBytes:avcC.pps()->Start() length:avcC.pps()->Length()];
    
    _videoSPSandPPS = [NSMutableData dataWithCapacity:avcC.sps()->Length() + avcC.pps()->Length() + _naluStartCode.length * 2];
    [_videoSPSandPPS appendData:_naluStartCode];
    [_videoSPSandPPS appendData:spsData];
    [_videoSPSandPPS appendData:_naluStartCode];
    [_videoSPSandPPS appendData:ppsData];
}

- (void) addOrphanedFramesFromArray:(NSArray*)frames {
    for (NSData *data in frames) {
        unsigned char* pNal = (unsigned char*)[data bytes];
        int idc = pNal[0] & 0x60;
        int naltype = pNal[0] & 0x1f;
        if (idc == 0 && naltype == 6) { // SEI
            DDLogVerbose(@"Orphaned SEI frame: idc(%d) naltype(%d) size(%lu)", idc, naltype, (unsigned long)data.length);
            [self.orphanedSEIFrames addObject:data];
        } else {
            DDLogVerbose(@"Orphaned frame: lastPTS:(%lld) idc(%d) naltype(%d) size(%lu)", _lastPTS.value, idc, naltype, (unsigned long)data.length);
            [self.orphanedFrames addObject:data];
        }
    }
}

- (void) writeVideoFrames:(NSArray*)frames pts:(CMTime)pts {
    NSMutableArray *totalFrames = [NSMutableArray array];
    if (self.orphanedSEIFrames.count > 0) {
        [totalFrames addObjectsFromArray:self.orphanedSEIFrames];
        [self.orphanedSEIFrames removeAllObjects];
    }
    [totalFrames addObjectsFromArray:frames];
    
    NSMutableData *aggregateFrameData = [NSMutableData data];
    NSData *sei = nil; // Supplemental enhancement information
    BOOL hasKeyframe = NO;
    for (NSData *data in totalFrames) {
        unsigned char* pNal = (unsigned char*)[data bytes];
        int idc = pNal[0] & 0x60;
        int naltype = pNal[0] & 0x1f;
        NSData *videoData = nil;
        
        
        if (idc == 0 && naltype == 6) { // SEI
            sei = data;
            continue;
        } else if (naltype == 5) { // IDR
            hasKeyframe = YES;
            NSMutableData *IDRData = [NSMutableData dataWithData:_videoSPSandPPS];
            if (sei) {
                [IDRData appendData:_naluStartCode];
                [IDRData appendData:sei];
                sei = nil;
            }
            [IDRData appendData:_naluStartCode];
            [IDRData appendData:data];
            videoData = IDRData;
        } else {
            NSMutableData *regularData = [NSMutableData dataWithData:_naluStartCode];
            [regularData appendData:data];
            videoData = regularData;
        }
        [aggregateFrameData appendData:videoData];
    }
    if (self.delegate) {
        KFVideoFrame *videoFrame = [[KFVideoFrame alloc] initWithData:aggregateFrameData pts:pts];
        videoFrame.isKeyFrame = hasKeyframe;
        dispatch_async(self.callbackQueue, ^{
            [self.delegate encoder:self encodedFrame:videoFrame];
        });
    }
}

#if 1
- (void) incomingVideoFrames:(NSArray*)frames ptsValue:(CMTimeValue)ptsValue {
    if (ptsValue == 0) {
        [self addOrphanedFramesFromArray:frames];
        return;
    }
    if (!_videoSPSandPPS) {
        [self generateSPSandPPS];
    }
    CMTime pts = CMTimeMake(ptsValue, _timescale);
    if (self.orphanedFrames.count > 0) {
        CMTime ptsDiff = CMTimeSubtract(pts, _lastPTS);
        NSUInteger orphanedFramesCount = self.orphanedFrames.count;
        DDLogVerbose(@"lastPTS before first orphaned frame: %lld", _lastPTS.value);
        for (NSData *frame in self.orphanedFrames) {
            CMTime fakePTSDiff = CMTimeMultiplyByFloat64(ptsDiff, 1.0/(orphanedFramesCount + 1));
            CMTime fakePTS = CMTimeAdd(_lastPTS, fakePTSDiff);
            DDLogVerbose(@"orphan frame fakePTS: %lld", fakePTS.value);
            [self writeVideoFrames:@[frame] pts:fakePTS];
        }
        DDLogVerbose(@"pts after orphaned frame: %lld", pts.value);
        [self.orphanedFrames removeAllObjects];
    }
    
    [self writeVideoFrames:frames pts:pts];
    _lastPTS = pts;
}
#else

- (void) incomingVideoFrames:(NSArray*)frames ptsValue:(CMTimeValue)ptsValue {
    if (ptsValue == 0) {
        [self addOrphanedFramesFromArray:frames];
        return;
    }
    if (!_videoSPSandPPS) {
        [self generateSPSandPPS];
    }
    CMTime pts = CMTimeMake(ptsValue, _timescale);
    if (self.orphanedFrames.count > 0) {
        CMTime ptsDiff = CMTimeSubtract(pts, _lastPTS);
        NSUInteger orphanedFramesCount = self.orphanedFrames.count;
        DDLogVerbose(@"lastPTS before first orphaned frame: %lld", _lastPTS.value);
        for (NSData *frame in self.orphanedFrames) {
            CMTime fakePTSDiff = CMTimeMultiplyByFloat64(ptsDiff, 1.0/(orphanedFramesCount + 1));
            CMTime fakePTS = CMTimeAdd(_lastPTS, fakePTSDiff);
            DDLogVerbose(@"orphan frame fakePTS: %lld", fakePTS.value);
            [self writeVideoFrames:@[frame] pts:fakePTS];
        }
        DDLogVerbose(@"pts after orphaned frame: %lld", pts.value);
        [self.orphanedFrames removeAllObjects];
    }
    
    [self writeVideoFrames:frames pts:pts];
    _lastPTS = pts;
}
#endif


@end
