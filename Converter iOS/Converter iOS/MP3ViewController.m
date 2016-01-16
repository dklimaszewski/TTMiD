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

#import <Accelerate/Accelerate.h>
#import <math.h>

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

@interface MP3ViewController () <EZAudioFileDelegate, EZAudioFFTDelegate, EZOutputDataSource, EZOutputDelegate> {
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

@property (assign, nonatomic) BOOL eof;
@property (strong, nonatomic) EZOutput *output;
@property (nonatomic, strong) EZAudioFFTRolling *fft;

@end

@implementation MP3ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.wavFilePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"wav"];
    self.inputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:self.wavFilePath]];
    
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
        const int PCM_SIZE = 32768;
        const int MP3_SIZE = 32768;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_out_samplerate(lame, 44100);
        lame_set_quality(lame, 2); // LAME_ENCODING_ENGINE_QUALITY
        lame_set_brate(lame, 64);
        lame_set_VBR(lame, vbr_off);
        lame_set_quality(lame, 1);
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
        OSStatus error = DoConvertFile(sourceURL, destinationURL, kAudioFormatLinearPCM, 44100, 0);
        
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
            });
            
        }
    }
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

#pragma mark- FFT
- (IBAction)doFFT:(id)sender {
    
    CFURLRef inputFileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                          (__bridge CFStringRef)self.wavFilePath,
                                                          kCFURLPOSIXPathStyle,
                                                          false);
    ExtAudioFileRef fileRef;
    ExtAudioFileOpenURL(inputFileURL, &fileRef);
    
    CFURLRef inputFileURL2 = CFURLCreateWithFileSystemPath(kCFAllocatorDefault,
                                                           (__bridge CFStringRef)self.destinationWAVFilePath,
                                                           kCFURLPOSIXPathStyle,
                                                           false);
    ExtAudioFileRef fileRef2;
    ExtAudioFileOpenURL(inputFileURL2, &fileRef2);
    
    AudioStreamBasicDescription audioFormat;
    audioFormat.mSampleRate = 44100;
    audioFormat.mFormatID = kAudioFormatLinearPCM;
    audioFormat.mFormatFlags = kLinearPCMFormatFlagIsFloat;
    audioFormat.mBitsPerChannel = sizeof(Float32) * 8;
    audioFormat.mChannelsPerFrame = 1; // Mono
    audioFormat.mBytesPerFrame = audioFormat.mChannelsPerFrame * sizeof(Float32);  // == sizeof(Float32)
    audioFormat.mFramesPerPacket = 1;
    audioFormat.mBytesPerPacket = audioFormat.mFramesPerPacket * audioFormat.mBytesPerFrame; // = sizeof(Float32)
    
    ExtAudioFileSetProperty(
                            fileRef,
                            kExtAudioFileProperty_ClientDataFormat,
                            sizeof (AudioStreamBasicDescription), //= audioFormat
                            &audioFormat);
    
    ExtAudioFileSetProperty(
                            fileRef2,
                            kExtAudioFileProperty_ClientDataFormat,
                            sizeof (AudioStreamBasicDescription), //= audioFormat
                            &audioFormat);
    
    int numSamples = 1024; //How many samples to read in at a time
    UInt32 sizePerPacket = audioFormat.mBytesPerPacket; // = sizeof(Float32) = 32bytes
    UInt32 packetsPerBuffer = numSamples;
    UInt32 outputBufferSize = packetsPerBuffer * sizePerPacket;
    
    UInt8 *outputBuffer = (UInt8 *)malloc(sizeof(UInt8 *) * outputBufferSize);
    UInt8 *outputBuffer2 = (UInt8 *)malloc(sizeof(UInt8 *) * outputBufferSize);
    
    AudioBufferList convertedData;
    convertedData.mNumberBuffers = 1;    // Set this to 1 for mono
    convertedData.mBuffers[0].mNumberChannels = audioFormat.mChannelsPerFrame;  //also = 1
    convertedData.mBuffers[0].mDataByteSize = outputBufferSize;
    convertedData.mBuffers[0].mData = outputBuffer; //
    
    AudioBufferList convertedData2;
    convertedData2.mNumberBuffers = 1;    // Set this to 1 for mono
    convertedData2.mBuffers[0].mNumberChannels = audioFormat.mChannelsPerFrame;  //also = 1
    convertedData2.mBuffers[0].mDataByteSize = outputBufferSize;
    convertedData2.mBuffers[0].mData = outputBuffer2; //
    
    UInt32 frameCount = numSamples;
    while (frameCount > 0) {
        ExtAudioFileRead(fileRef, &frameCount, &convertedData);
        ExtAudioFileRead(fileRef2, &frameCount, &convertedData2);
        
        
        if (frameCount > 0)  {
            AudioBuffer audioBuffer = convertedData.mBuffers[0];
            float *samples = (float *)audioBuffer.mData;
            
            AudioBuffer audioBuffer2 = convertedData2.mBuffers[0];
            float *samples2 = (float *)audioBuffer2.mData;
            
            
            float z[numSamples];
            float z2[numSamples];
            float sd = 0;
            
            for (int k=1; k<=frameCount; k++) {
                float ak = 0;
                float bk = 0;
                
                float ak2 = 0;
                float bk2 = 0;
                
                for (int n=1; n<=frameCount; n++) {
                    float alfa = (-2*M_PI*n*k)/frameCount;
                    
                    ak = ak + samples[n-1] * cosf(alfa);
                    bk = bk + samples[n-1] * sinf(alfa);
                    
                    ak2 = ak2 + samples2[n-1] * cosf(alfa);
                    bk2 = bk2 + samples2[n-1] * sinf(alfa);
                }
                
                z[k-1] = sqrtf(powf(ak, 2) + powf(bk, 2));
                z2[k-1] = sqrtf(powf(ak2, 2) + powf(bk2, 2));
                
                
                sd = sd + powf(10*log10f(z[k-1])-10*log10f(z2[k-1]), 2)/frameCount;

            }
            
            printf("%f\n", sd);
            
        } else {
            NSLog(@"Finished");
        }
    }
}

@end
