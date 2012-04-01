//
//  ViewController.m
//  BackgroundAudioTest
//
//  Created by Pontago on 12/03/29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"


void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer);
void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID);

void audioQueueOutputCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueueBufferRef inBuffer) {

    ViewController *viewController = (__bridge ViewController*)inClientData;
    [viewController audioQueueOutputCallback:inAQ inBuffer:inBuffer];
}

void audioQueueIsRunningCallback(void *inClientData, AudioQueueRef inAQ,
  AudioQueuePropertyID inID) {

    ViewController *viewController = (__bridge ViewController*)inClientData;
    [viewController audioQueueIsRunningCallback];
}

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setCategory:AVAudioSessionCategoryPlayback error:nil];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.

    [self removeAudioQueue];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
    } else {
        return YES;
    }
}

- (IBAction)playAudio:(UIButton*)sender {
    [self startAudio_];
}

- (IBAction)pauseAudio:(UIButton*)sender {
    if (started_) {
      state_ = AUDIO_STATE_PAUSE;

      AudioQueuePause(audioQueue_);
      AudioQueueReset(audioQueue_);

      SInt64 pausePacket = (kNumAQBufs * audioStreamBasicDesc_.mSampleRate) / audioStreamBasicDesc_.mFramesPerPacket;
      currentPacket_ -= pausePacket;
    }
}

- (IBAction)stopAudio:(UIButton*)sender {
    [self stopAudio_];
}

- (IBAction)updateSeekSlider:(UISlider*)sender {
    if (started_) {
      state_ = AUDIO_STATE_SEEKING;

      SInt64 seekPacket = (seekSlider_.value * audioStreamBasicDesc_.mSampleRate) / audioStreamBasicDesc_.mFramesPerPacket;
      AudioQueueStop(audioQueue_, YES);
      currentPacket_ = seekPacket;
      startedTime_ = seekSlider_.value;

      [self startAudio_];
    }
}

- (void)updatePlaybackTime:(NSTimer*)timer {
    AudioTimeStamp timeStamp;
    OSStatus status = AudioQueueGetCurrentTime(audioQueue_, NULL, &timeStamp, NULL);

    if (status == noErr) {
      SInt64 time = floor(durationTime_);
      NSTimeInterval currentTimeInterval = timeStamp.mSampleTime / audioStreamBasicDesc_.mSampleRate;
      SInt64 currentTime = floor(startedTime_ + currentTimeInterval);
      seekLabel_.text = [NSString stringWithFormat:@"%02llu:%02llu:%02llu / %02llu:%02llu:%02llu",
        ((currentTime / 60) / 60), (currentTime / 60), (currentTime % 60),
        ((time / 60) / 60), (time / 60), (time % 60)];

      seekSlider_.value = startedTime_ + currentTimeInterval;
    }
}


- (void)startAudio_ {
    if (started_) {
      AudioQueueStart(audioQueue_, NULL);
    }
    else {
      playingFilePath_ = [[NSBundle mainBundle] pathForResource:@"sample" ofType:@"mp3"];
      fileNameLabel_.text = [playingFilePath_ lastPathComponent];

      if (![self createAudioQueue]) {
        abort();
      }
      [self startQueue];

      seekTimer_ = [NSTimer scheduledTimerWithTimeInterval:1.0
        target:self selector:@selector(updatePlaybackTime:) userInfo:nil repeats:YES];
    }

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      [self enqueueBuffer:audioQueueBuffer_[i]];
    }

    state_ = AUDIO_STATE_PLAYING;
}

- (void)stopAudio_ {
    if (started_) {
      AudioQueueStop(audioQueue_, YES);
      currentPacket_ = 0;
      seekSlider_.value = 0.0;
      startedTime_ = 0.0;

      SInt64 time = floor(durationTime_);
      seekLabel_.text = [NSString stringWithFormat:@"0 / %02llu:%02llu:%02llu",
        ((time / 60) / 60), (time / 60), (time % 60)];

      state_ = AUDIO_STATE_STOP;
      finished_ = NO;
    }
}

- (BOOL)createAudioQueue {
    state_ = AUDIO_STATE_READY;
    finished_ = NO;

    OSStatus status = AudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:playingFilePath_], 
      kAudioFileReadPermission, 0, &inAudioID_);
    if (status != noErr) return NO;

    UInt32 size = sizeof(audioStreamBasicDesc_);
    status = AudioFileGetProperty(inAudioID_, kAudioFilePropertyDataFormat, 
      &size, &audioStreamBasicDesc_);
    if (status != noErr) return NO;

    if (audioStreamBasicDesc_.mFormatID != kAudioFormatMPEGLayer3) {
      NSLog(@"The audio format was not supported.");
      return NO;
    }


    startedTime_ = 0.0;
    size = sizeof(durationTime_);
    status = AudioFileGetProperty(inAudioID_, kAudioFilePropertyEstimatedDuration, &size, &durationTime_);
    if (status == noErr) {
      dispatch_async(dispatch_get_main_queue(), ^{
        SInt64 time = floor(durationTime_);
        seekLabel_.text = [NSString stringWithFormat:@"0 / %02llu:%02llu:%02llu",
          ((time / 60) / 60), (time / 60), (time % 60)];

        seekSlider_.maximumValue = durationTime_;
      });
    }


    UInt32 bufferByteSize;
    UInt32 maxPacketSize;
    size = sizeof(maxPacketSize);
    status = AudioFileGetProperty(inAudioID_, kAudioFilePropertyPacketSizeUpperBound, &size, &maxPacketSize);
    if (status == noErr) {
      [self calculateBytesForTime:maxPacketSize inSeconds:kBufferDurationSeconds 
        outBufferSize:&bufferByteSize outNumPackets:&numPacketsToRead_];
    }


    status = AudioQueueNewOutput(&audioStreamBasicDesc_, audioQueueOutputCallback, (__bridge void*)self,
      NULL, NULL, 0, &audioQueue_);
    if (status != noErr) {
      NSLog(@"Could not create new output.");
      return NO;
    }

    status = AudioQueueAddPropertyListener(audioQueue_, kAudioQueueProperty_IsRunning, 
      audioQueueIsRunningCallback, (__bridge void*)self);
    if (status != noErr) {
      NSLog(@"Could not add propery listener. (kAudioQueueProperty_IsRunning)");
      return NO;
    }


    currentPacket_ = 0;
//    SInt64 seekPacket = (60.0 * audioStreamBasicDesc_.mSampleRate) / audioStreamBasicDesc_.mFramesPerPacket;
//    currentPacket_ = seekPacket;

    BOOL isFormatVBR = (audioStreamBasicDesc_.mBytesPerPacket == 0 || audioStreamBasicDesc_.mFramesPerPacket == 0);
    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      status = AudioQueueAllocateBufferWithPacketDescriptions(audioQueue_, 
        bufferByteSize, (isFormatVBR ? numPacketsToRead_ : 0), &audioQueueBuffer_[i]);
      if (status != noErr) {
        NSLog(@"Could not allocate buffer.");
        return NO;
      }
    }

    return YES;
}

- (void)removeAudioQueue {
    [self stopAudio_];
    started_ = NO;

    for (NSInteger i = 0; i < kNumAQBufs; ++i) {
      AudioQueueFreeBuffer(audioQueue_, audioQueueBuffer_[i]);
    }
    AudioQueueDispose(audioQueue_, YES);
    AudioFileClose(inAudioID_);
}


- (void)audioQueueOutputCallback:(AudioQueueRef)inAQ inBuffer:(AudioQueueBufferRef)inBuffer {
    if (state_ == AUDIO_STATE_PLAYING) {
      [self enqueueBuffer:inBuffer];
    }
}

- (void)audioQueueIsRunningCallback {
    UInt32 isRunning;
    UInt32 size = sizeof(isRunning);
    OSStatus status = AudioQueueGetProperty(audioQueue_, kAudioQueueProperty_IsRunning, &isRunning, &size);

    if (status == noErr && !isRunning && state_ == AUDIO_STATE_PLAYING) {
      state_ = AUDIO_STATE_STOP;

      if (finished_) {
        SInt64 time = floor(durationTime_);
        seekLabel_.text = [NSString stringWithFormat:@"%02llu:%02llu:%02llu / %02llu:%02llu:%02llu",
          ((time / 60) / 60), (time / 60), (time % 60),
          ((time / 60) / 60), (time / 60), (time % 60)];
      }
    }
}


- (OSStatus)enqueueBuffer:(AudioQueueBufferRef)buffer {
    OSStatus status = noErr;
    UInt32 numBytesRead, numPackets = numPacketsToRead_;

    status = AudioFileReadPackets(inAudioID_, NO, &numBytesRead, buffer->mPacketDescriptions,
      currentPacket_, &numPackets, buffer->mAudioData);
    if (numPackets > 0) {
      buffer->mAudioDataByteSize = numBytesRead;
      buffer->mPacketDescriptionCount = numPackets;
      AudioQueueEnqueueBuffer(audioQueue_, buffer, 0, NULL);

      currentPacket_ += numPackets;
    }
    else {
      AudioQueueStop(audioQueue_, NO);
      finished_ = YES;
    }

    return status;
}

- (OSStatus)startQueue {
    OSStatus status = noErr;

    if (!started_) {
      status = AudioQueueStart(audioQueue_, NULL);
      if (status == noErr) {
        started_ = YES;
      }
      else {
        NSLog(@"Could not start audio queue.");
      }
    }

    return status;
}

- (void)calculateBytesForTime:(UInt32)inMaxPacketSize inSeconds:(NSTimeInterval)inSeconds 
  outBufferSize:(UInt32*)outBufferSize outNumPackets:(UInt32*)outNumPackets {

  static const int maxBufferSize = 0x10000; // limit size to 64K
  static const int minBufferSize = 0x4000; // limit size to 16K

  if (audioStreamBasicDesc_.mFramesPerPacket) {
    NSTimeInterval numPacketsForTime = 
      audioStreamBasicDesc_.mSampleRate / audioStreamBasicDesc_.mFramesPerPacket * inSeconds;
    *outBufferSize = numPacketsForTime * inMaxPacketSize;
  } 
  else {
    // if frames per packet is zero, then the codec has no predictable packet == time
    // so we can't tailor this (we don't know how many Packets represent a time period
    // we'll just return a default buffer size
    *outBufferSize = maxBufferSize > inMaxPacketSize ? maxBufferSize : inMaxPacketSize;
  }

  // we're going to limit our size to our default
  if (*outBufferSize > maxBufferSize && *outBufferSize > inMaxPacketSize) {
    *outBufferSize = maxBufferSize;
  }
  else {
    // also make sure we're not too small - we don't want to go the disk for too small chunks
    if (*outBufferSize < minBufferSize)
      *outBufferSize = minBufferSize;
  }
  *outNumPackets = *outBufferSize / inMaxPacketSize;
}

@end
