//
//  ViewController.h
//  BackgroundAudioTest
//
//  Created by Pontago on 12/03/29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>

#define kNumAQBufs 3
#define kAQDefaultBufSize 4096
#define kBufferDurationSeconds .5

typedef enum _AUDIO_STATE {
  AUDIO_STATE_READY           = 0,
  AUDIO_STATE_STOP            = 1,
  AUDIO_STATE_PLAYING         = 2,
  AUDIO_STATE_PAUSE           = 3,
  AUDIO_STATE_SEEKING         = 4
} AUDIO_STATE;

@interface ViewController : UIViewController {
  NSString *playingFilePath_;
  AudioFileID inAudioID_;
  AudioStreamBasicDescription audioStreamBasicDesc_;
  AudioQueueRef audioQueue_;
  AudioQueueBufferRef audioQueueBuffer_[kNumAQBufs];
  BOOL started_, finished_;
  NSTimeInterval durationTime_, startedTime_;
  SInt64 currentPacket_;
  UInt32 numPacketsToRead_;
  NSInteger state_;
  NSTimer *seekTimer_;

  IBOutlet UILabel *fileNameLabel_, *seekLabel_;
  IBOutlet UISlider *seekSlider_;
  IBOutlet UIButton *playButton_, *stopButton_, *pauseButton_;
}


- (IBAction)playAudio:(UIButton*)sender;
- (IBAction)stopAudio:(UIButton*)sender;
- (IBAction)pauseAudio:(UIButton*)sender;
- (IBAction)updateSeekSlider:(UISlider*)sender;
- (void)updatePlaybackTime:(NSTimer*)timer;

- (void)startAudio_;
- (void)stopAudio_;
- (BOOL)createAudioQueue;
- (void)removeAudioQueue;
- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer;
- (void)audioQueueIsRunningCallback;
- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer;
- (OSStatus)startQueue;
- (void)calculateBytesForTime:(UInt32)inMaxPacketSize inSeconds:(NSTimeInterval)inSeconds 
  outBufferSize:(UInt32*)outBufferSize outNumPackets:(UInt32*)outNumPackets;

@end
