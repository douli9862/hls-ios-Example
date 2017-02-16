//
//  mediaProcess.h
//  mediaProcess
//
//  Created by tzx on 16/11/17.
//  Copyright © 2016年 tzx. All rights reserved.
//

#ifndef AMEDIAPROCESSSS_H
#define AMEDIAPROCESSSS_H

//bool createVideoPool(void **mediaPool, int width, int height, int MediaType);

bool createAudioPool(void **mediaPool, int frameSize, int num);

void DestoryMediaPool(void *mediaPool);

bool pushAudioFrame(void *audioPool, unsigned char *inAudioFrame, int frameSize);

bool getAudioFrameBegin(void *audioPool, unsigned char **inAudioFrame, int *frameSize);

void getAudioFrameEnd(void *audioPool);

//bool pushVideoFrame(void *videoPool, unsigned char *data, int len, int width, int height, int rawType);

//bool getVideoFrameBegin(void *VideoPool, unsigned char **inFrame, int* width, int* height, int* frameSize);
//
//void getVideoFrameEnd(void *VideoPool);


#endif
