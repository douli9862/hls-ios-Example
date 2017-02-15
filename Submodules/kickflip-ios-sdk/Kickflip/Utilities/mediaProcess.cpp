//
//  mediaProcess.m
//  mediaProcess
//
//  Created by tzx on 16/11/17.
//  Copyright © 2016年 tzx. All rights reserved.
//

#include "mediaProcess.h"
//#include "mediaPool/AudioFrameBufferPool.h"
#include "AudioFrameBufferPool.h"
//#include "mediaPool/VideoFrameBufferPool.h"
//#include "LibyuvColorSpaceConvert.h"


static  MediaStreamer::VideoFrame   mI420;
//static  ColorSpaceConvert           *mColorSpaceConvert = NULL;

bool createAudioPool(void **mediaPool, int frameSize, int num)
{
    *mediaPool = new MediaData::AudioFrameBufferPool(frameSize, num);
    if(*mediaPool == NULL){
        return false;
    }

    return true;
}


void DestoryMediaPool(void *mediaPool)
{
    delete  mediaPool;
}


bool pushAudioFrame(void *audioPool, unsigned char *inAudioFrame, int frameSize)
{
    MediaData::AudioFrameBufferPool  *ptAudioPool = (MediaData::AudioFrameBufferPool*)audioPool;
    if(ptAudioPool != NULL){
        ptAudioPool->pushAudioFrame(inAudioFrame, frameSize);
        
        return true;
    }
    
    return false;
}


bool getAudioFrameBegin(void *audioPool, unsigned char **inAudioFrame, int *frameSize){
    MediaData::AudioFrameBufferPool  *ptAudioPool = (MediaData::AudioFrameBufferPool*)audioPool;
    if(ptAudioPool == NULL){
        return false;
    }
    
    MediaStreamer::AudioFrame* audioFrame_ = NULL;
    if(NULL == ptAudioPool){
        return false;
    }
    
    audioFrame_ =  ptAudioPool->front();//frontAudioFrame();
    if(audioFrame_ == NULL){
        //NSLog(@"audioFrame_ == NULL");
        return false;
    }
    *inAudioFrame = audioFrame_->data;
    *frameSize = audioFrame_->frameSize;

    return true;
}

void getAudioFrameEnd(void *audioPool){
    MediaData::AudioFrameBufferPool  *ptAudioPool = (MediaData::AudioFrameBufferPool*)audioPool;
    if(ptAudioPool == NULL){
        return ;
    }
    ptAudioPool->pop();
}


//bool pushVideoFrame(void *videoPool, unsigned char *data, int len, int width, int height, int rawType)
//{
//    MediaData::VideoFrameBufferPool  *ptVideoPool = (MediaData::VideoFrameBufferPool*)videoPool;
//    if(ptVideoPool == NULL){
//        
//        return true;
//    }
//    
//    if(data == NULL){
//        return  false;
//    }
//    
//    MediaStreamer::VideoFrame vdFrame;
//    vdFrame.data = data;
//    vdFrame.frameSize = len;
//    vdFrame.width = width;
//    vdFrame.height = height;
//    vdFrame.pts = 0;
//    vdFrame.rotation = 0;
//    vdFrame.videoRawType = rawType;
//    
//    mColorSpaceConvert->ARGBtoI420(&vdFrame, &mI420);
//    
//    ptVideoPool->push(&mI420);
//
//    return false;
//}


//bool getVideoFrameBegin(void *VideoPool, unsigned char **inFrame, int &frameSize){
//    MediaData::AudioFrameBufferPool  *ptVideoPool = (MediaData::AudioFrameBufferPool*)VideoPool;
//    if(ptVideoPool == NULL){
//        return false;
//    }
//    
//    MediaStreamer::AudioFrame* audioFrame_ = NULL;
//    if(NULL == ptVideoPool){
//        return false;
//    }
//    
//    audioFrame_ =  ptVideoPool->front();
//    if(audioFrame_ == NULL){
//        //NSLog(@"audioFrame_ == NULL");
//        return false;
//    }
//    *inAudioFrame = audioFrame_->data;
//    frameSize = audioFrame_->frameSize;
//    
//    return true;
//}


//bool getVideoFrameBegin(void *VideoPool, unsigned char **inFrame, int* width, int* height, int *frameSize){
//    MediaData::VideoFrameBufferPool  *ptVideoPool = (MediaData::VideoFrameBufferPool*)VideoPool;
//    if(ptVideoPool == NULL){
//        return false;
//    }
//
//    MediaStreamer::VideoFrame * vdFrame = ptVideoPool->front();
//    if(vdFrame == NULL){
//        return  false;
//    }
//    
//    *inFrame = vdFrame->data;
//    *frameSize = vdFrame->frameSize;
//    *width   = vdFrame->width;
//    *height  = vdFrame->height;
//    
//    //mVideoFrameBufferPool->pop();
//    
//    return true;
//}
//
//
//void getVideoFrameEnd(void *VideoPool){
//    MediaData::VideoFrameBufferPool  *ptVideoPool = (MediaData::VideoFrameBufferPool*)VideoPool;
//    if(ptVideoPool == NULL){
//        return;
//    }
//    
//    ptVideoPool->pop();
//}



