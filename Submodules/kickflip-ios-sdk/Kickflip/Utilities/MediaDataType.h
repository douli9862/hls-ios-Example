//
//  MediaDataType.h
//  MediaStreamer
//
//  Created by Think on 16/2/14.
//  Copyright © 2016年 Cell. All rights reserved.
//

#ifndef MediaStreamer_MediaDataType_h
#define MediaStreamer_MediaDataType_h

#include <vector>
#include <stdlib.h>

#define MAX_VIDEO_FRAME_SIZE 1280*720*3/2 //1920*1080*3/2

using namespace std;

namespace MediaStreamer {
 

enum {
    VIDEOFRAME_RAWTYPE_I420 = 0x0001,
    VIDEOFRAME_RAWTYPE_NV12 = 0x0002,
    VIDEOFRAME_RAWTYPE_NV21 = 0x0003,
    VIDEOFRAME_RAWTYPE_BGRA = 0x0004,
    VIDEOFRAME_RAWTYPE_RGBA = 0x0005
};

struct VideoOptions
{
    bool hasVideo;
    int videoWidth;
    int videoHeight;
    int videoFps;
    int videoRawType;
    
    int videoBitRate;
    int encodeMode; //0:VBR or 1:CBR
    int quality; //[-5, 5]:CRF
    int maxKeyFrameIntervalMs;
    bool bStrictCBR;
    int deblockingFilterFactor; //[-6, 6] -6 light filter, 6 strong
    
    VideoOptions()
    {
        hasVideo = true;
        videoWidth = 1280;
        videoHeight = 720;
        videoFps = 15;
        videoRawType = VIDEOFRAME_RAWTYPE_I420;
        
        videoBitRate = 1500000;
        encodeMode = 0;
        quality = 0;
        maxKeyFrameIntervalMs = 3000;
        bStrictCBR = false;
        deblockingFilterFactor = 0;
    }
};

struct AudioOptions
{
    bool hasAudio;
    int audioSampleRate;
    int audioNumChannels;
    int audioBitRate;
    
    AudioOptions()
    {
        hasAudio = true;
        audioSampleRate = 44100;
        audioNumChannels = 1;
        audioBitRate = 128000;
    }
};

//------------------------------------------------------------

struct VideoFrame
{
    uint8_t *data;
    int frameSize;
    
    int width;
    int height;
    
    int64_t pts;
    
    int rotation;
    
    int videoRawType;
    
    VideoFrame()
    {
        data = NULL;
        frameSize = 0;
        pts = 0;
        rotation = 0;
        videoRawType = VIDEOFRAME_RAWTYPE_NV21;
    }
};


struct AudioFrame
{
    uint8_t *data;
    int frameSize;
    
    int duration; //ms
    
    int64_t     pts;
    
    AudioFrame()
    {
        data = NULL;
        frameSize  = 0;
        duration = 0;
        pts = 0;
    }
};

//------------------------------------------------------------

enum Video_Packet_Priority
{
    VIDEO_PACKET_PRIORITY_DISPOSABLE = 0,
    VIDEO_PACKET_PRIORITY_LOW        = 1,
    VIDEO_PACKET_PRIORITY_HIGH       = 2,
    VIDEO_PACKET_PRIORITY_HIGHEST    = 3,
};

struct Nal
{
    uint8_t *data;
    int size;
    
    Nal()
    {
        data = NULL;
        size = 0;
    }
};

struct VideoPacket
{
    vector<Nal*> nals;
    int nal_Num;
    
    int ref_idc; //Video Packet Priority
    
    int64_t pts;
    int64_t dts;

    VideoPacket()
    {
        nal_Num = 0;
        ref_idc = VIDEO_PACKET_PRIORITY_DISPOSABLE;
        
        pts = 0;
        dts = 0;
    }
    
    inline void Clear()
    {
        for(vector<Nal*>::iterator it = nals.begin(); it != nals.end(); ++it)
        {
            Nal* nal = *it;
            
            if(nal!=NULL)
            {
                delete nal;
                nal = NULL;
            }
        }
        
        nals.clear();
        
        nal_Num = 0;
        ref_idc = VIDEO_PACKET_PRIORITY_DISPOSABLE;
        
        pts = 0;
        dts = 0;
    }
    
    inline void Free()
    {
        for(vector<Nal*>::iterator it = nals.begin(); it != nals.end(); ++it)
        {
            Nal* nal = *it;
            
            if(nal!=NULL)
            {
                if(nal->data!=NULL)
                {
                    free(nal->data);
                    nal->data = NULL;
                }
                
                delete nal;
                nal = NULL;
            }
        }
        
        nals.clear();
        
        nal_Num = 0;
        ref_idc = VIDEO_PACKET_PRIORITY_DISPOSABLE;
        
        pts = 0;
        dts = 0;
    }
};

struct AudioPacket
{
    uint8_t *data;
    int size;

    int64_t pts;
    int64_t dts;

    AudioPacket()
    {
        data = NULL;
        size = 0;
        
        pts = 0;
        dts = 0;
    }
};

struct TextPacket
{
    uint8_t *data;
    int size;

    int64_t     pts;

    TextPacket()
    {
        data = NULL;
        size = 0;
        
        pts = 0;
    }
};

enum Media_Packet_Type
{
    MEDIA_PACKET_UNKNOWN = -1,
    
    VIDEO_H264_SPS_PPS = 0,
    VIDEO_H264_KEY_FRAME = 1,
    VIDEO_H264_P_OR_B_FRAME = 2,

    AUDIO_AAC_HEADER = 3,
    AUDIO_AAC_BODY = 4,

    TEXT = 5,
};

struct MediaPacket
{
    Media_Packet_Type packetType;

    uint8_t *data;
    int size;
    
    int64_t pts;
    int64_t dts;
    
    MediaPacket()
    {
        packetType = MEDIA_PACKET_UNKNOWN;
        data = NULL;
        size = 0;
        
        pts = 0;
        dts = 0;
    }
};
    
}

#endif
