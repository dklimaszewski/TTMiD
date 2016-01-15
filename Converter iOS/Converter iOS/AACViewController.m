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
    
    //22050.0 -> 32000
    //44100.0 -> 64000, 128000
    self.outputSettings = [NSMutableDictionary dictionaryWithDictionary:@{
                                                                          AVFormatIDKey : @(kAudioFormatMPEG4AAC),
                                                                          AVSampleRateKey : @(44100.0),
                                                                          AVEncoderBitRateKey : @(64000)
                                                                          }];
    
    [self convert];
}

- (void)convert {
    
    NSLog(@"Destination File Path: %@", self.destinationAACFilePath);
    
    AVAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:self.wavFilePath] options:nil];
    
    NSURL *exportURL = [NSURL fileURLWithPath:self.destinationAACFilePath];
    
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
            [self.outputSettings setObject:@(asbd->mChannelsPerFrame) forKey:AVNumberOfChannelsKey];
            
            AudioChannelLayout channelLayout;
            memset(&channelLayout, 0, sizeof(AudioChannelLayout));
            if (asbd->mChannelsPerFrame == 1) {
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Mono;
            } else {
                channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
            }
            
            [self.outputSettings setObject:[NSData dataWithBytes:&channelLayout length:sizeof(AudioChannelLayout)] forKey:AVChannelLayoutKey];
        }
    }
    
    AVAssetWriterInput *writerInput = [[AVAssetWriterInput alloc] initWithMediaType:AVMediaTypeAudio
                                                                     outputSettings:self.outputSettings];
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
                                    
                                    [self performSelector:@selector(showOutputWAVWaveform) withObject:nil afterDelay:1.0];
                                    
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
                    
                    [self performSelector:@selector(compareAudioFiles) withObject:nil afterDelay:1.0];
                });
            }
        }
    }
}

- (void)compareAudioFiles {
    
    /*__block NSMutableArray *inputFileAmplitudes;
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
     
     }];*/
    
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
