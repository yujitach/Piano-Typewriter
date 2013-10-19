//
//  YTAppDelegate.h
//  Piano Typewriter
//
//  Created by Yuji on 2013/10/15.
//  Copyright (c) 2013年 Yuji Tachikawa. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface YTAppDelegate : NSObject <NSApplicationDelegate>

@property (assign) IBOutlet NSWindow *window;
@property (assign) IBOutlet NSPopUpButton *button;
-(IBAction)openPref:(id)sender;
-(IBAction)soundChanged:(id)sender;
@end
