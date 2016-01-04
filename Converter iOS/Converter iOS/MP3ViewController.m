//
//  MP3ViewController.m
//  Converter iOS
//
//  Created by Michal Czwarnowski on 04.01.2016.
//  Copyright © 2016 Michał Czwarnowski. All rights reserved.
//

#import "MP3ViewController.h"
#import "lame.h"
#import <EZAudio.h>
#import <FDWaveformView.h>

#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#include "CAXException.h"
#include "CAStreamBasicDescription.h"

extern OSStatus DoConvertFile(CFURLRef sourceURL, CFURLRef destinationURL, OSType outputFormat, Float64 outputSampleRate, UInt32 outputBitRate);

static void UpdateFormatInfo(CFURLRef inFileURL)
{
    AudioFileID fileID;
    
    OSStatus result = AudioFileOpenURL(inFileURL, kAudioFileReadPermission, 0, &fileID);
    if (noErr == result) {
        CAStreamBasicDescription asbd;
        UInt32 size = sizeof(asbd);
        result = AudioFileGetProperty(fileID, kAudioFilePropertyDataFormat, &size, &asbd);
        if (noErr == result) {
            char formatID[5];
            CFStringRef lastPathComponent = CFURLCopyLastPathComponent(inFileURL);
            *(UInt32 *)formatID = CFSwapInt32HostToBig(asbd.mFormatID);
            
            NSString *result = [NSString stringWithFormat: @"%@ %4.4s %6.0f Hz (%u ch.)", lastPathComponent, formatID, asbd.mSampleRate, (unsigned int)(asbd.NumberChannels()), nil];
            NSLog(@"%@", result);
            CFRelease(lastPathComponent);
        } else {
            printf("AudioFileGetProperty kAudioFilePropertyDataFormat result %d %4.4s\n", (int)result, (char*)&result);
        }
        
        AudioFileClose(fileID);
    } else {
        printf("AudioFileOpenURL failed! result %d %4.4s\n", (int)result, (char*)&result);
    }
}

@interface MP3ViewController () {
    CFURLRef sourceURL;
    CFURLRef destinationURL;
}

@property (weak, nonatomic) IBOutlet FDWaveformView *inputAudioView;
@property (weak, nonatomic) IBOutlet FDWaveformView *wavAudioView;

@property (strong, nonatomic) EZAudioFile *inputAudioFile;
@property (strong, nonatomic) EZAudioFile *outputAudioFile;

@property (strong, nonatomic) NSString *mp3FilePath;
@property (strong, nonatomic) NSString *wavFilePath;
@property (strong, nonatomic) NSString *destinationMP3FilePath;
@property (strong, nonatomic) NSString *destinationWAVFilePath;

@end

@implementation MP3ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.wavFilePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"wav"];
    
    [self showInputWAVWaveform];
}

#pragma mark- WAV->MP3
- (IBAction)convertWavToMp3:(id)sender {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    self.destinationMP3FilePath = [[NSString alloc] initWithFormat: @"%@/output_mp3.mp3", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.destinationMP3FilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.destinationMP3FilePath error:nil];
    }
    
    @try {
        int read, write;
        FILE *pcm = fopen([self.wavFilePath cStringUsingEncoding:1], "rb");
        FILE *mp3 = fopen([self.destinationMP3FilePath cStringUsingEncoding:1], "wb");
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, 44100);
        lame_set_out_samplerate(lame, 22050);
        lame_set_VBR(lame, vbr_default);
        lame_set_quality(lame, 7);
        lame_set_VBR_quality(lame, 7);
        lame_init_params(lame);
        
        do {
            read = (int)fread(pcm_buffer, 2*sizeof(short int), PCM_SIZE, pcm);
            if (read == 0)
                write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            else
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
            
            fwrite(mp3_buffer, write, 1, mp3);
            
        } while (read != 0);
        
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
    }
    @catch (NSException *exception) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:[NSString stringWithFormat:@"Converter fail - %@", [exception description]] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
    @finally {
        //Detrming the size of mp3 file
        NSFileManager *fileManger = [NSFileManager defaultManager];
        NSData *data = [fileManger contentsAtPath:self.destinationMP3FilePath];
        NSString *str = [NSString stringWithFormat:@"%lu K",[data length]/1024];
        NSLog(@"size of mp3=%@",str);
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"YAY!!!" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}

#pragma mark- MP3->WAV

- (IBAction)convertMP3toWAV:(id)sender {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    self.mp3FilePath = [[NSString alloc] initWithFormat: @"%@/output_mp3.mp3", documentsDirectory];
    sourceURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)self.mp3FilePath, kCFURLPOSIXPathStyle, false);
    
    self.destinationWAVFilePath = [[NSString alloc] initWithFormat: @"%@/output_mp3.wav", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.destinationWAVFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.destinationWAVFilePath error:nil];
    }
    
    NSLog(@"Destination File Path: %@", self.destinationWAVFilePath);
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)self.destinationWAVFilePath, kCFURLPOSIXPathStyle, false);
    
    UpdateFormatInfo(sourceURL);
    
    [self convertMP3];
}

- (void)convertMP3 {
    NSError *error = nil;
    [[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryAudioProcessing error:&error];
    if (error) {
        printf("Setting the AVAudioSessionCategoryAudioProcessing Category failed! %ld\n", (long)error.code);
        
        return;
    }
    
    // run audio file code in a background thread
    [self performSelectorInBackground:(@selector(convertAudio)) withObject:nil];
}

#pragma mark- ExtAudioFile

- (void)convertAudio {
    @autoreleasepool {
        OSStatus error = DoConvertFile(sourceURL, destinationURL, kAudioFormatLinearPCM, 0, 0);
        
        if (error) {
            // delete output file if it exists since an error was returned during the conversion process
            if ([[NSFileManager defaultManager] fileExistsAtPath:self.destinationWAVFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:self.destinationWAVFilePath error:nil];
            }
            
            printf("DoConvertFile failed! %d\n", (int)error);
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"Converter fail" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
            });
            
        } else {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"YAY!!!" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:alert animated:YES completion:nil];
                
                [self performSelector:@selector(showOutputWAVWaveform) withObject:nil afterDelay:1.0];
                
                [self performSelector:@selector(compareAudioFiles) withObject:nil afterDelay:1.0];
            });
            
        }
    }
}

- (void)compareAudioFiles {
    
    __block NSMutableArray *inputFileAmplitudes;
    __block NSMutableArray *outputFileAmplitudes;
    __block NSMutableArray *amplitudesDifference;
    
    self.inputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:self.wavFilePath]];
    
    [self.inputAudioFile getWaveformDataWithCompletionBlock:^(float **waveformData, int length) {
        inputFileAmplitudes = [[NSMutableArray alloc] initWithCapacity:length];
        
        for (int i=0; i<length; i++) {
            [inputFileAmplitudes addObject:@(waveformData[0][i])];
        }
        
        self.outputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:self.destinationWAVFilePath]];
        [self.outputAudioFile getWaveformDataWithCompletionBlock:^(float **waveformData, int length) {
            outputFileAmplitudes = [[NSMutableArray alloc] initWithCapacity:length];
            
            for (int i=0; i<length; i++) {
                [outputFileAmplitudes addObject:@(waveformData[0][i])];
            }
            
            amplitudesDifference = [[NSMutableArray alloc] initWithCapacity:length];
            
            for (int i=0; i<length; i++) {
                [amplitudesDifference addObject:@([outputFileAmplitudes[i] floatValue] - [inputFileAmplitudes[i] floatValue])];
            }
            
            NSLog(@"%@", amplitudesDifference);
            
        }];
        
    }];
    
}

#pragma mark- FDWaveformView Plots

- (void)showInputWAVWaveform {
    
    self.inputAudioView.wavesColor = [UIColor redColor];
    self.inputAudioView.audioURL = [NSURL fileURLWithPath:self.wavFilePath];
    
}

- (void)showOutputWAVWaveform {
    
    self.wavAudioView.wavesColor = [UIColor blueColor];
    self.wavAudioView.audioURL = [NSURL fileURLWithPath:self.destinationWAVFilePath];
    
}

@end
