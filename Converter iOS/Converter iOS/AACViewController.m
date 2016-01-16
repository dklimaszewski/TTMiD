//
//  AACViewController.m
//  Converter iOS
//
//  Created by Michał Czwarnowski on 29.11.2015.
//  Copyright © 2015 Michał Czwarnowski. All rights reserved.
//

#import "AACViewController.h"
#import <EZAudio.h>
#import <FDWaveformView.h>
#import "TPAACAudioConverter.h"
#import <AVFoundation/AVFoundation.h>

extern OSStatus DoConvertFile(CFURLRef sourceURL, CFURLRef destinationURL, OSType outputFormat, Float64 outputSampleRate, UInt32 outputBitRate);

#define kTransitionDuration	0.75

#pragma mark-

static Boolean IsAACEncoderAvailable(void)
{
    Boolean isAvailable = false;
    
    // get an array of AudioClassDescriptions for all installed encoders for the given format
    // the specifier is the format that we are interested in - this is 'aac ' in our case
    UInt32 encoderSpecifier = kAudioFormatMPEG4AAC;
    UInt32 size;
    
    OSStatus result = AudioFormatGetPropertyInfo(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size);
    if (result) { printf("AudioFormatGetPropertyInfo kAudioFormatProperty_Encoders result %d %4.4s\n", (int)result, (char*)&result); return false; }
    
    UInt32 numEncoders = size / sizeof(AudioClassDescription);
    AudioClassDescription encoderDescriptions[numEncoders];
    
    result = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, encoderDescriptions);
    if (result) { printf("AudioFormatGetProperty kAudioFormatProperty_Encoders result %d %4.4s\n", (int)result, (char*)&result); return false; }
    
    printf("Number of AAC encoders available: %u\n", (unsigned int)numEncoders);
    
    // with iOS 7.0 AAC software encode is always available
    // older devices like the iPhone 4s also have a slower/less flexible hardware encoded for supporting AAC encode on older systems
    // newer devices may not have a hardware AAC encoder at all but a faster more flexible software AAC encoder
    // as long as one of these encoders is present we can convert to AAC
    // if both are available you may choose to which one to prefer via the AudioConverterNewSpecific() API
    for (UInt32 i=0; i < numEncoders; ++i) {
        if (encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleHardwareAudioCodecManufacturer) {
            printf("Hardware encoder available\n");
            isAvailable = true;
        }
        if (encoderDescriptions[i].mSubType == kAudioFormatMPEG4AAC && encoderDescriptions[i].mManufacturer == kAppleSoftwareAudioCodecManufacturer) {
            printf("Software encoder available\n");
            isAvailable = true;
        }
    }
    
    return isAvailable;
}

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

@interface AACViewController () <TPAACAudioConverterDelegate> {
    CFURLRef sourceURL;
    CFURLRef destinationURL;
    OSType   outputFormat;
}

@property (weak, nonatomic) IBOutlet FDWaveformView *inputAudioView;
@property (weak, nonatomic) IBOutlet FDWaveformView *wavAudioView;

@property (strong, nonatomic) EZAudioFile *inputAudioFile;
@property (strong, nonatomic) EZAudioFile *outputAudioFile;

@property (strong, nonatomic) NSString *aacFilePath;
@property (strong, nonatomic) NSString *wavFilePath;
@property (strong, nonatomic) NSString *destinationAACFilePath;
@property (strong, nonatomic) NSString *destinationWAVFilePath;
@property (strong, nonatomic) NSMutableDictionary *outputSettings;

@property (nonatomic) TPAACAudioConverter *audioConverter;

@end

@implementation AACViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.wavFilePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"wav"];
    
    [self showInputWAVWaveform];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark- WAV->AAC

- (IBAction)convertWAVtoAAC:(id)sender {
    
    outputFormat = kAudioFormatMPEG4AAC;
    
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    self.destinationAACFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.destinationAACFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.destinationAACFilePath error:nil];
    }
    
    //44100.0 -> 64000, 128000, 256000
    self.outputSettings = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                          AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                                          AVSampleRateKey : @(44100.0),
                                                                          AVEncoderBitRateKey : @(64000)
                                                                          }];
    
    [self convert];
}

- (void)convert {
    if ( ![TPAACAudioConverter AACConverterAvailable] ) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Converting audio" message:@"Couldn't convert audio: Not supported on this device" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(audioSessionInterrupted:)
                                                 name:AVAudioSessionInterruptionNotification
                                               object:nil];
    
    NSError *error = nil;
    if ( ![[AVAudioSession sharedInstance] setCategory:AVAudioSessionCategoryPlayback
                                           withOptions:0
                                                 error:&error] ) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Converting audio" message:[NSString stringWithFormat:@"Couldn't setup audio category: %@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        return;
    }
    
    if ( ![[AVAudioSession sharedInstance] setActive:YES error:NULL] ) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Converting audio" message:[NSString stringWithFormat:@"Couldn't activate audio category: %@", error.localizedDescription] preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        return;
    }
    
    self.audioConverter = [[TPAACAudioConverter alloc] initWithDelegate:self
                                                                 source:self.wavFilePath
                                                            destination:self.destinationAACFilePath];
    
    self.audioConverter.outputSettings = self.outputSettings;
    
    [self.audioConverter start];
}

#pragma mark- AAC->WAV

- (IBAction)convertAACtoWAV:(id)sender {
    outputFormat = kAudioFormatLinearPCM;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    self.aacFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    sourceURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)self.aacFilePath, kCFURLPOSIXPathStyle, false);
    
    self.destinationWAVFilePath = [[NSString alloc] initWithFormat: @"%@/output.wav", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.destinationWAVFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:self.destinationWAVFilePath error:nil];
    }
    
    NSLog(@"Destination File Path: %@", self.destinationWAVFilePath);
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)self.destinationWAVFilePath, kCFURLPOSIXPathStyle, false);
    
    if (IsAACEncoderAvailable()) {
        NSLog(@"AAC is available");
    } else {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"AAC not available" preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    UpdateFormatInfo(sourceURL);
    
    [self convertAAC];
}

- (void)convertAAC {
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
        OSStatus error = DoConvertFile(sourceURL, destinationURL, outputFormat, 44100, 0);
        
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
            
            if (outputFormat == kAudioFormatMPEG4AAC) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                });
                
            } else if (outputFormat == kAudioFormatLinearPCM) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"YAY!!!" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                    
                    [self performSelector:@selector(showOutputWAVWaveform) withObject:nil afterDelay:1.0];
                });
            }
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

#pragma mark- TPAACAudioConverter

- (void)AACAudioConverter:(TPAACAudioConverter *)converter didFailWithError:(NSError *)error {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Error" message:@"Converter fail" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)AACAudioConverterDidFinishConversion:(TPAACAudioConverter *)converter {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"YAY!!!" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark- Audio session interruption

- (void)audioSessionInterrupted:(NSNotification*)notification {
    NSNumber *interruptionType = notification.userInfo[AVAudioSessionInterruptionTypeKey];
    
    AVAudioSessionInterruptionType type = [interruptionType unsignedIntegerValue] == 1 ? AVAudioSessionInterruptionTypeBegan : AVAudioSessionInterruptionTypeEnded;
    
    if ( type == AVAudioSessionInterruptionTypeEnded) {
        [[AVAudioSession sharedInstance] setActive:YES error:NULL];
        if ( _audioConverter ) [_audioConverter resume];
    } else if ( type == AVAudioSessionInterruptionTypeBegan ) {
        if ( _audioConverter ) [_audioConverter interrupt];
    }
}

@end
