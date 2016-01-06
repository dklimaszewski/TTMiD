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

- (void)playAudioFile {
    [self.inputAudioFile setDelegate:self];
    
    self.fft = [EZAudioFFTRolling fftWithWindowSize:1024
                                         sampleRate:self.inputAudioFile.clientFormat.mSampleRate
                                           delegate:self];
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSError *error;
    [session setCategory:AVAudioSessionCategoryPlayback error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session category: %@", error.localizedDescription);
    }
    [session setActive:YES error:&error];
    if (error)
    {
        NSLog(@"Error setting up audio session active: %@", error.localizedDescription);
    }
    
    self.output = [EZOutput outputWithDataSource:self];
    self.output.delegate = self;
    
    [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker error:&error];
    if (error)
    {
        NSLog(@"There was an error sending the audio to the speakers");
    }
    
    
    if (![self.output isPlaying]) {
        [self.output setDataSource:self];
        [self.output startPlayback];
    }
}

#pragma mark- EZAudioFile Delegates
- (OSStatus)output:(EZOutput *)output shouldFillAudioBufferList:(AudioBufferList *)audioBufferList withNumberOfFrames:(UInt32)frames timestamp:(const AudioTimeStamp *)timestamp {
    if (self.inputAudioFile) {
        
        UInt32 bufferSize;
        [self.inputAudioFile readFrames:frames
                        audioBufferList:audioBufferList
                             bufferSize:&bufferSize
                                    eof:&_eof];
    }
    
    return 0;
}

- (void)audioFile:(EZAudioFile *)audioFile readAudio:(float **)buffer withBufferSize:(UInt32)bufferSize withNumberOfChannels:(UInt32)numberOfChannels {
    [self.fft computeFFTWithBuffer:buffer[0] withBufferSize:bufferSize];
}

- (void)        fft:(EZAudioFFT *)fft
 updatedWithFFTData:(float *)fftData
         bufferSize:(vDSP_Length)bufferSize
{
    float maxFrequency = [fft maxFrequency];
    NSString *noteName = [EZAudioUtilities noteNameStringForFrequency:maxFrequency
                                                        includeOctave:YES];
    
    __weak typeof (self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        //        weakSelf.maxFrequencyLabel.text =
        NSLog(@"%@", [NSString stringWithFormat:@"Highest Note: %@,\nFrequency: %.2f", noteName, maxFrequency]);
        //        [weakSelf.audioPlotFreq updateBuffer:fftData withBufferSize:(UInt32)bufferSize];
    });
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
            
            vDSP_Length log2n = log2f(numSamples);
            
            // Calculate the weights array. This is a one-off operation.
            FFTSetup fftSetup = vDSP_create_fftsetup(log2n, FFT_RADIX2);
            FFTSetup fftSetup2 = vDSP_create_fftsetup(log2n, FFT_RADIX2);
            
            // For an FFT, numSamples must be a power of 2, i.e. is always even
            int nOver2 = numSamples/2;
            
            // Populate *window with the values for a hamming window function
            float *window = (float *)malloc(sizeof(float) * numSamples);
            vDSP_hamm_window(window, numSamples, 0);
            // Window the samples
            vDSP_vmul(samples, 1, window, 1, samples, 1, numSamples);
            free(window);
            
            float *window2 = (float *)malloc(sizeof(float) * numSamples);
            vDSP_hamm_window(window2, numSamples, 0);
            // Window the samples
            vDSP_vmul(samples2, 1, window2, 1, samples2, 1, numSamples);
            free(window2);
            
            // Define complex buffer
            COMPLEX_SPLIT A;
            A.realp = (float *) malloc(nOver2*sizeof(float));
            A.imagp = (float *) malloc(nOver2*sizeof(float));
            
            COMPLEX_SPLIT B;
            B.realp = (float *) malloc(nOver2*sizeof(float));
            B.imagp = (float *) malloc(nOver2*sizeof(float));
            
            // Pack samples:
            // C(re) -> A[n], C(im) -> A[n+1]
            vDSP_ctoz((COMPLEX*)samples, 2, &A, 1, numSamples/2);
            vDSP_ctoz((COMPLEX*)samples2, 2, &B, 1, numSamples/2);
            
            //Perform a forward FFT using fftSetup and A
            //Results are returned in A
            vDSP_fft_zrip(fftSetup, &A, 1, log2n, FFT_FORWARD);
            vDSP_fft_zrip(fftSetup2, &B, 1, log2n, FFT_FORWARD);
            
            //Convert COMPLEX_SPLIT A result to magnitudes
            float amp[numSamples];
            float z[numSamples];
            
            float amp2[numSamples];
            float z2[numSamples];
            
            amp[0] = A.realp[0]/(numSamples*2);
            amp2[0] = B.realp[0]/(numSamples*2);
            for(int i=1; i<numSamples; i++) {
                amp[i]=A.realp[i]*A.realp[i]+A.imagp[i]*A.imagp[i];
                amp2[i]=B.realp[i]*B.realp[i]+B.imagp[i]*B.imagp[i];
                
                z[i] = sqrtf(amp[i]);
                z2[i] = sqrtf(amp2[i]);
            }
            
            float sd = 0;
            for (int i=0; i<numSamples; i++) {
                sd = sd + powf(10*log10f(z[i])-10*log10f(z2[i]), 2)/numSamples;
            }
            
            printf("%f\n", sd);
            
        } else {
            NSLog(@"Finished");
        }
    }
}

@end
