//
//  ViewController.m
//  TTMiD
//
//  Created by Damian Klimaszewski on 08.11.2015.
//  Copyright © 2015 Damian & Michał. All rights reserved.
//

#import "ViewController.h"
#import <CSIOpusCodec/CSIOpusCodec.h>

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UIButton *readAudioButton;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

- (IBAction)readAudioAction:(id)sender {
    
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"M1F1-Alaw-AFsp" withExtension:@"wav"];
    NSData *data = [NSData dataWithContentsOfURL:url];
    /*AVURLAsset *audioAsset = [AVURLAsset URLAssetWithURL:url options:nil];

    
    AVAsset *asset = [AVURLAsset URLAssetWithURL:audioAsset.URL options:nil];

    NSError *error;
    
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    
    NSMutableDictionary *audioReadSettings = [NSMutableDictionary dictionary];
    [audioReadSettings setValue:[NSNumber numberWithInt:kAudioFormatLinearPCM]
                         forKey:AVFormatIDKey];
    
    AVAssetReaderTrackOutput *readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:audioReadSettings];
    [reader addOutput:readerOutput];
    [reader startReading];*/
    
    NSDictionary *options = @{ AVURLAssetPreferPreciseDurationAndTimingKey : @YES,
                               AVFormatIDKey : @(kAudioFormatLinearPCM) };
    AVURLAsset *anAssetToUseInAComposition = [[AVURLAsset alloc] initWithURL:url options:options];
    
    if (![[anAssetToUseInAComposition tracksWithMediaType:AVMediaTypeAudio] count]) {
        return;
    }
    
    AVAssetTrack *track = [[anAssetToUseInAComposition tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    AVAssetReaderTrackOutput *readerOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:@{ AVFormatIDKey : @(kAudioFormatLinearPCM) }];
    
    NSError *error;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:anAssetToUseInAComposition error:&error];
    [reader addOutput:readerOutput];
    [reader startReading];
    
    CMSampleBufferRef sample = [readerOutput copyNextSampleBuffer];
    
    while (sample != NULL) {
        sample = [readerOutput copyNextSampleBuffer];
        
        if(sample == NULL)
            continue;
        
        CMBlockBufferRef buffer = CMSampleBufferGetDataBuffer(sample);
        
        size_t lengthAtOffset;
        size_t totalLength;
        char *data;
        
        if (CMBlockBufferGetDataPointer(buffer, 0, &lengthAtOffset, &totalLength, &data) != noErr) {
            NSLog(@"error!");
            break;
        }
        
        //TU NA OPUSA!
        CFRelease(sample);
    }
}

- (IBAction)convertToOpus:(id)sender {
    
}

@end
