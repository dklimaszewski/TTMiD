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

@interface AACViewController () {
    NSString *aacFilePath;
    NSString *wavFilePath;
    
    NSString *destinationAACFilePath;
    NSString *destinationWAVFilePath;
    
    NSMutableDictionary *outputSettings;
    
    CFURLRef sourceURL;
    CFURLRef destinationURL;
    OSType   outputFormat;
    Float64  sampleRate;
}

@property (weak, nonatomic) IBOutlet FDWaveformView *inputAudioView;
@property (weak, nonatomic) IBOutlet FDWaveformView *wavAudioView;

@property (strong, nonatomic) EZAudioFile *inputAudioFile;
@property (strong, nonatomic) EZAudioFile *outputAudioFile;

@end

@implementation AACViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
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
    destinationAACFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationAACFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destinationAACFilePath error:nil];
    }
    
    wavFilePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"wav"];
    
    outputSettings = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                     AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                                     AVSampleRateKey : @(44100.0),
                                                                     AVEncoderBitRateKey : @(128000)
                                                                     }];
    
    [self convert];
}

- (void)convert {
    
    NSLog(@"Destination File Path: %@", destinationAACFilePath);
    
    AVAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:wavFilePath] options:nil];
    
    NSURL *exportURL = [NSURL fileURLWithPath:destinationAACFilePath];
    
    // reader
    NSError *readerError = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset
                                                           error:&readerError];
    
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] objectAtIndex:0];
    NSArray *formatDesc = track.formatDescriptions;
    
    AVAssetReaderTrackOutput *readerOutput = [[AVAssetReaderTrackOutput alloc] initWithTrack:track
                                                                              outputSettings:nil];
    [reader addOutput:readerOutput];
    
    // writer
    NSError *writerError = nil;
    AVAssetWriter *writer = [[AVAssetWriter alloc] initWithURL:exportURL
                                                      fileType:AVFileTypeAppleM4A
                                                         error:&writerError];
    
    
    for(unsigned int i=0; i<[formatDesc count]; i++) {
        CMAudioFormatDescriptionRef item = (__bridge CMAudioFormatDescriptionRef)[formatDesc objectAtIndex:i];
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription (item);
        if(asbd) {
            [outputSettings setObject:@(asbd->mChannelsPerFrame) forKey:AVNumberOfChannelsKey];
            
            AudioChannelLayout channelLayout;
            memset(&channelLayout, 0, sizeof(AudioChannelLayout));
            if (asbd->mChannelsPerFrame == 1) {
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
            } else {
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
            }
            
            [outputSettings setObject:[NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)] forKey:AVChannelLayoutKey];
        }
    }
    
    AVAssetWriterInput *writerInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                                     outputSettings:outputSettings];
    [writerInput setExpectsMediaDataInRealTime:NO];
    [writer addInput:writerInput];
    
    [writer startWriting];
    [writer startSessionAtSourceTime:kCMTimeZero];
    
    [reader startReading];
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue", NULL);
    [writerInput requestMediaDataWhenReadyOnQueue:mediaInputQueue usingBlock:^{
        
        NSLog(@"Asset Writer ready : %d", writerInput.readyForMoreMediaData);
        while (writerInput.readyForMoreMediaData) {
            CMSampleBufferRef nextBuffer;
            if ([reader status] == AVAssetReaderStatusReading && (nextBuffer = [readerOutput copyNextSampleBuffer])) {
                if (nextBuffer) {
                    NSLog(@"Adding buffer");
                    [writerInput appendSampleBuffer:nextBuffer];
                }
            } else {
                [writerInput markAsFinished];
                
                switch ([reader status]) {
                    case AVAssetReaderStatusReading:
                        break;
                    case AVAssetReaderStatusFailed:
                    case AVAssetReaderStatusCancelled:
                    case AVAssetReaderStatusUnknown:
                        [writer cancelWriting];
                        break;
                    case AVAssetReaderStatusCompleted:
                        NSLog(@"Writer completed");
                        [writer endSessionAtSourceTime:asset.duration];
                        [writer finishWritingWithCompletionHandler:^{
                            NSLog(@"Finished converting");
                            
                            if (outputFormat == kAudioFormatMPEG4AAC) {
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
                                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                                    [self presentViewController:alert animated:YES completion:nil];
                                });
                                
                            } else if (outputFormat == kAudioFormatLinearPCM) {
                                
                                dispatch_async(dispatch_get_main_queue(), ^{
                                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Success!" message:@"Audio Converted" preferredStyle:UIAlertControllerStyleAlert];
                                    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                                    [self presentViewController:alert animated:YES completion:nil];
                                    
                                    [self performSelector:@selector(showWAVWaveform) withObject:nil afterDelay:1.0];
                                    
                                    [self performSelector:@selector(compareAudioFiles) withObject:nil afterDelay:1.0];
                                });
                            }
                            
                        }];
                        break;
                }
                break;
            }
        }
    }];
}

#pragma mark- AAC->WAV

- (IBAction)convertAACtoWAV:(id)sender {
    outputFormat = kAudioFormatLinearPCM;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    aacFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    sourceURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)aacFilePath, kCFURLPOSIXPathStyle, false);
    
    destinationWAVFilePath = [[NSString alloc] initWithFormat: @"%@/output.wav", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationWAVFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destinationWAVFilePath error:nil];
    }
    
    NSLog(@"Destination File Path: %@", destinationWAVFilePath);
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationWAVFilePath, kCFURLPOSIXPathStyle, false);
    
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
        OSStatus error = DoConvertFile(sourceURL, destinationURL, outputFormat, sampleRate, 64000);
        
        if (error) {
            // delete output file if it exists since an error was returned during the conversion process
            if ([[NSFileManager defaultManager] fileExistsAtPath:destinationWAVFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:destinationWAVFilePath error:nil];
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
                    
                    [self performSelector:@selector(showWAVWaveform) withObject:nil afterDelay:1.0];
                    
                    [self performSelector:@selector(compareAudioFiles) withObject:nil afterDelay:1.0];
                });
                
            }
            
        }
    }
    
    
}

- (void)compareAudioFiles {
    
    __block NSMutableArray *inputFileAmplitudes;
    __block NSMutableArray *outputFileAmplitudes;
    __block NSMutableArray *amplitudesDifference;
    
    self.inputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:wavFilePath]];
    
    [self.inputAudioFile getWaveformDataWithCompletionBlock:^(float **waveformData, int length) {
        inputFileAmplitudes = [[NSMutableArray alloc] initWithCapacity:length];
        
        for (int i=0; i<length; i++) {
            [inputFileAmplitudes addObject:@(waveformData[0][i])];
        }
        
        self.outputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:destinationWAVFilePath]];
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
    
    NSString *sourceFilePath = [[NSBundle mainBundle] pathForResource:@"a2002011001-e02" ofType:@"wav"];
    
    self.inputAudioView.wavesColor = [UIColor redColor];
    self.inputAudioView.audioURL = [NSURL fileURLWithPath:sourceFilePath];
    
}

- (void)showWAVWaveform {
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *sourceFilePath = [[NSString alloc] initWithFormat: @"%@/output.wav", documentsDirectory];
    
    self.wavAudioView.wavesColor = [UIColor blueColor];
    self.wavAudioView.audioURL = [NSURL fileURLWithPath:sourceFilePath];
    
}
@end
