//
//  AudioFrameBufferPool.h
//  MediaStreamer
//
//  Created by Think on 16/2/14.
//  Copyright © 2016年 Cell. All rights reserved.
//

#ifndef __MediaStreamer__AudioFrameBufferPool__
#define __MediaStreamer__AudioFrameBufferPool__

#include <vector>
#include <pthread.h>

#include "MediaDataType.h"

//struct AudioFrame
//{
//    uint8_t *data;
//    int frameSize;
//    
//    int duration; //ms
//    
//    uint64_t pts;
//    
//    AudioFrame()
//    {
//        data = NULL;
//        frameSize  = 0;
//        duration = 0;
//        pts = 0;
//    }
//};

#define MAX_AUDIOFRAME_BUFFER_NUM 4
#define MAX_AUDIOFRAME_BUFFER_SIZE 44100*2*2

using namespace std;

namespace MediaData {
    class AudioFrameBufferPool
    {
    public:
        AudioFrameBufferPool();
        AudioFrameBufferPool(int audioFrameSize, int num);
        AudioFrameBufferPool(int sampleRate, int channelCount, int bitsPerSample, int duration, int num);
        ~AudioFrameBufferPool();
        
        bool push(MediaStreamer::AudioFrame *audioFrame);
        MediaStreamer::AudioFrame* front();
        void pop();
        
        void flush();
        
        void pushAudioFrame(unsigned char *inAudioFrame, int frameSize);
    private:
        pthread_mutex_t mLock;
        vector<MediaStreamer::AudioFrame*> mAudioFrameBuffers;
        
        int capacity;
        
        int write_pos;
        int read_pos;
        int buffer_num;
        
        MediaStreamer::AudioFrame   mAudioFrame;
        int                         mAudioSize;
        bool                        mLastBufNotNil;
    };
}



#endif /* defined(__MediaStreamer__AudioFrameBufferPool__) */
