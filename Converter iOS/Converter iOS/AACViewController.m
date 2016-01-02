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
    if (result) { printf("AudioFormatGetPropertyInfo kAudioFormatProperty_Encoders result %lu %4.4s\n", result, (char*)&result); return false; }
    
    UInt32 numEncoders = size / sizeof(AudioClassDescription);
    AudioClassDescription encoderDescriptions[numEncoders];
    
    result = AudioFormatGetProperty(kAudioFormatProperty_Encoders, sizeof(encoderSpecifier), &encoderSpecifier, &size, encoderDescriptions);
    if (result) { printf("AudioFormatGetProperty kAudioFormatProperty_Encoders result %lu %4.4s\n", result, (char*)&result); return false; }
    
    printf("Number of AAC encoders available: %lu\n", numEncoders);
    
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
    NSString *destinationFilePath;
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
    
//    [self compareAudioFiles];
    [self showInputWAVWaveform];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)convertWAVtoAAC:(id)sender {
    outputFormat = kAudioFormatMPEG4AAC;//kAudioFormatMPEG4AAC_HE_V2
    
    NSString *source = [[NSBundle mainBundle] pathForResource:@"a2002011001-e02" ofType:@"wav"];
    sourceURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)source, kCFURLPOSIXPathStyle, false);
    
    NSArray  *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    destinationFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destinationFilePath error:nil];
    }
    
    NSLog(@"Destination File Path: %@", destinationFilePath);
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationFilePath, kCFURLPOSIXPathStyle, false);
    
    if (IsAACEncoderAvailable()) {
        NSLog(@"AAC is available");
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"AAC not available" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        
        return;
    }
    
    UpdateFormatInfo(sourceURL);
    
    [self convert];
}

- (IBAction)convertAACtoWAV:(id)sender {
    outputFormat = kAudioFormatLinearPCM;
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *sourceFilePath = [[NSString alloc] initWithFormat: @"%@/output.m4a", documentsDirectory];
    CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)sourceFilePath, kCFURLPOSIXPathStyle, false);
    
    destinationFilePath = [[NSString alloc] initWithFormat: @"%@/output.wav", documentsDirectory];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFilePath]) {
        [[NSFileManager defaultManager] removeItemAtPath:destinationFilePath error:nil];
    }
    
    NSLog(@"Destination File Path: %@", destinationFilePath);
    destinationURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)destinationFilePath, kCFURLPOSIXPathStyle, false);
    
    if (IsAACEncoderAvailable()) {
        NSLog(@"AAC is available");
    } else {
        [[[UIAlertView alloc] initWithTitle:@"Error" message:@"AAC not available" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
        
        return;
    }
    
    UpdateFormatInfo(sourceURL);
    
    [self convert];
}

- (void)convert {
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

- (void)convertAudio
{
    @autoreleasepool {
        OSStatus error = DoConvertFile(sourceURL, destinationURL, outputFormat, sampleRate, 64000);
        
        if (error) {
            // delete output file if it exists since an error was returned during the conversion process
            if ([[NSFileManager defaultManager] fileExistsAtPath:destinationFilePath]) {
                [[NSFileManager defaultManager] removeItemAtPath:destinationFilePath error:nil];
            }
            
            printf("DoConvertFile failed! %d\n", (int)error);
            dispatch_async(dispatch_get_main_queue(), ^{
                [[[UIAlertView alloc] initWithTitle:@"Error" message:@"Converter fail" delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil] show];
            });
            
        } else {
            
            if (outputFormat == kAudioFormatMPEG4AAC) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[UIAlertView alloc] initWithTitle:@"Success!" message:@"Audio Converted" delegate:nil cancelButtonTitle:@"YAY!!!" otherButtonTitles:nil] show];
                });
                
            } else if (outputFormat == kAudioFormatLinearPCM) {
                
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[UIAlertView alloc] initWithTitle:@"Success!" message:@"Audio Converted" delegate:nil cancelButtonTitle:@"YAY!!!" otherButtonTitles:nil] show];
                    
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
    
    NSString *sourceFilePath = [[NSBundle mainBundle] pathForResource:@"a2002011001-e02" ofType:@"wav"];
    self.inputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:sourceFilePath]];
    
    [self.inputAudioFile getWaveformDataWithCompletionBlock:^(float **waveformData, int length) {
        inputFileAmplitudes = [[NSMutableArray alloc] initWithCapacity:length];
        
        for (int i=0; i<length; i++) {
            [inputFileAmplitudes addObject:@(waveformData[0][i])];
        }
        
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString *outputFilePath = [[NSString alloc] initWithFormat: @"%@/output.wav", documentsDirectory];
//        NSString *outputFilePath = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"wav"];
        
        self.outputAudioFile = [EZAudioFile audioFileWithURL:[NSURL fileURLWithPath:outputFilePath]];
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
