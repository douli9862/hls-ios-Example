//
//  AudioFrameBufferPool.cpp
//  MediaStreamer
//
//  Created by Think on 16/2/14.
//  Copyright © 2016年 Cell. All rights reserved.
//

#include <stdlib.h>
#include "AudioFrameBufferPool.h"

namespace MediaData {

AudioFrameBufferPool::AudioFrameBufferPool()
{
    for(int i=0; i<MAX_AUDIOFRAME_BUFFER_NUM;i++)
    {
        MediaStreamer::AudioFrame *audioFrame = new MediaStreamer::AudioFrame;
        audioFrame->data = (uint8_t*)malloc(MAX_AUDIOFRAME_BUFFER_SIZE);
        audioFrame->frameSize = MAX_AUDIOFRAME_BUFFER_SIZE;
        mAudioFrameBuffers.push_back(audioFrame);
    }
    
    capacity = MAX_AUDIOFRAME_BUFFER_NUM;
    
    pthread_mutex_init(&mLock, NULL);
    
    write_pos = 0;
    read_pos = 0;
    buffer_num = 0;
}

AudioFrameBufferPool::AudioFrameBufferPool(int audioFrameSize, int num)
{
    mAudioSize = audioFrameSize;
    mAudioFrame.data = (uint8_t*)malloc(mAudioSize);
    mAudioFrame.frameSize = mAudioSize;

    for(int i=0; i<num;i++)
    {
        MediaStreamer::AudioFrame *audioFrame = new MediaStreamer::AudioFrame;
        audioFrame->data = (uint8_t*)malloc(audioFrameSize);
        audioFrame->frameSize = audioFrameSize;
        mAudioFrameBuffers.push_back(audioFrame);
    }
    
    capacity = num;
    
    pthread_mutex_init(&mLock, NULL);
    
    write_pos = 0;
    read_pos = 0;
    buffer_num = 0;
}

AudioFrameBufferPool::AudioFrameBufferPool(int sampleRate, int channelCount, int bitsPerSample, int duration, int num)
{
    int audioFrameSize = sampleRate*channelCount*bitsPerSample/8*duration/1000;
    
    for(int i=0; i<num;i++)
    {
        MediaStreamer::AudioFrame *audioFrame = new MediaStreamer::AudioFrame;
        audioFrame->data = (uint8_t*)malloc(audioFrameSize);
        audioFrame->frameSize = audioFrameSize;
        mAudioFrameBuffers.push_back(audioFrame);
    }
    
    capacity = num;
    
    pthread_mutex_init(&mLock, NULL);
    
    write_pos = 0;
    read_pos = 0;
    buffer_num = 0;
}

AudioFrameBufferPool::~AudioFrameBufferPool()
{
    flush();
    
    for(vector<MediaStreamer::AudioFrame*>::iterator it = mAudioFrameBuffers.begin(); it != mAudioFrameBuffers.end(); ++it)
    {
        MediaStreamer::AudioFrame* audioFrame = *it;
        
        if (audioFrame!=NULL) {
            if (audioFrame->data!=NULL) {
                free(audioFrame->data);
                audioFrame->data = NULL;
            }
            
            delete audioFrame;
            audioFrame = NULL;
        }
    }
    
    mAudioFrameBuffers.clear();
    
    pthread_mutex_destroy(&mLock);
}

bool AudioFrameBufferPool::push(MediaStreamer::AudioFrame* audioFrame)
{
    if (audioFrame==NULL) return false;
    if (audioFrame->data==NULL) return false;
    
    pthread_mutex_lock(&mLock);
    
    if (buffer_num>=capacity) {
        // is full
        pthread_mutex_unlock(&mLock);

        //LOGE("AudioFrameBufferPool:: push() failed, is full");

        return false;
    }
    
    if (write_pos>=capacity) {
        write_pos = 0;
    }
    
    memcpy(mAudioFrameBuffers[write_pos]->data, audioFrame->data, audioFrame->frameSize);
    mAudioFrameBuffers[write_pos]->frameSize = audioFrame->frameSize;
    mAudioFrameBuffers[write_pos]->duration = audioFrame->duration;
    mAudioFrameBuffers[write_pos]->pts = audioFrame->pts;
    
    write_pos++;
    buffer_num++;
    
    pthread_mutex_unlock(&mLock);

    return true;
}

MediaStreamer::AudioFrame* AudioFrameBufferPool::front()
{
    pthread_mutex_lock(&mLock);
    
    if (buffer_num<=0) {
        // is empty
        pthread_mutex_unlock(&mLock);
        return NULL;
    }else {
        if (read_pos>=capacity) {
            read_pos = 0;
        }
        int readPos = read_pos;
        pthread_mutex_unlock(&mLock);
        
        return mAudioFrameBuffers[readPos];
    }
}

void AudioFrameBufferPool::pop()
{
    pthread_mutex_lock(&mLock);
    
    read_pos++;
    buffer_num--;
    
    pthread_mutex_unlock(&mLock);
}

void AudioFrameBufferPool::flush()
{
    pthread_mutex_lock(&mLock);
    write_pos = 0;
    read_pos = 0;
    buffer_num = 0;
    pthread_mutex_unlock(&mLock);
}
    
    void AudioFrameBufferPool::pushAudioFrame(unsigned char *inAudioFrame, int frameSize)
    {
        MediaStreamer::AudioFrame audioFrame_;
        uint8_t *pData_ = inAudioFrame;
        int frameSize_ = frameSize;
        
        if(frameSize_ <= mAudioSize)
        {
            if(false == mLastBufNotNil)
            {
                memcpy(mAudioFrame.data, pData_, frameSize_);
                mAudioFrame.frameSize = frameSize_;
                if(frameSize_ == mAudioSize)
                {
                    push(&mAudioFrame);
                    return;
                }
                else
                {
                    mLastBufNotNil = true;
                }
            }
            else
            {
                int nTemp = mAudioSize - mAudioFrame.frameSize;
                if(frameSize_ >= nTemp)
                {
                    memcpy(mAudioFrame.data + mAudioFrame.frameSize, pData_, nTemp);
                    mAudioFrame.frameSize += nTemp;
                    pData_ += nTemp;
                    push(&mAudioFrame);
                    int nLeft = frameSize_ - nTemp;
                    if(nLeft == 0)
                    {
                        return;
                    }
                    else
                    {
                        memcpy(mAudioFrame.data, pData_, nLeft);
                        mAudioFrame.frameSize = nLeft;
                        mLastBufNotNil = true;
                    }
                }
                else
                {
                    memcpy(mAudioFrame.data + mAudioFrame.frameSize, pData_, frameSize_);
                    mAudioFrame.frameSize += frameSize_;
                    mLastBufNotNil = true;
                    return;
                }
            }
        }
        
        if (frameSize_ > mAudioSize)
        {
            if (true == mLastBufNotNil){
                int nTemp = mAudioSize - mAudioFrame.frameSize;
                memcpy(mAudioFrame.data + mAudioFrame.frameSize, pData_, nTemp);
                mAudioFrame.frameSize = mAudioSize;
                
                push(&mAudioFrame);
                pData_ += nTemp;
                frameSize_ -=nTemp;
                mAudioFrame.frameSize = mAudioSize;
            }
            
            int nFrame = frameSize_ / mAudioSize;
            //LOGI("frameSize_:%d, nFrame:%d", frameSize_, nFrame);
            
            for (int i = 0; i < nFrame; ++i){
                
                audioFrame_.frameSize = mAudioSize;
                audioFrame_.data = pData_;
                pData_ += mAudioSize;
                frameSize_ -= mAudioSize;
                push(&audioFrame_);
            }
            
            if(frameSize_ > 0){
                memcpy(mAudioFrame.data, pData_, frameSize_);
                mAudioFrame.frameSize = frameSize_;
                //mAudioFrame.pts = lastPts + diffPts;
                mLastBufNotNil = true;
            }else{
                mLastBufNotNil = false;
            }
        }

    }

}
