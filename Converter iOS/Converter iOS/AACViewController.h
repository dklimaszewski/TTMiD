//
//  AACViewController.h
//  Converter iOS
//
//  Created by Michał Czwarnowski on 29.11.2015.
//  Copyright © 2015 Michał Czwarnowski. All rights reserved.
//

// includes
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

// helpers
#include "CAXException.h"
#include "CAStreamBasicDescription.h"

@interface AACViewController : UIViewController <AVAudioPlayerDelegate>

@end
