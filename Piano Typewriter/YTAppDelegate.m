//
//  YTAppDelegate.m
//  Piano Typewriter
//
//  Created by Yuji on 2013/10/15.
//  Copyright (c) 2013年 Yuji Tachikawa. All rights reserved.
//

// Icon is taken from http://www.iconarchive.com/show/cold-fusion-hd-icons-by-chrisbanks2/piano-2-icon.html

#import "YTAppDelegate.h"
#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudio/CoreAudioTypes.h>

enum {
    kMIDIMessage_NoteOn    = 0x9,
    kMIDIMessage_NoteOff   = 0x8,
};


@interface YTAppDelegate ()
@property (readwrite) Float64   graphSampleRate;
@property (readwrite) AUGraph   processingGraph;
@property (readwrite) AudioUnit samplerUnit;
@property (readwrite) AudioUnit ioUnit;

- (OSStatus)    loadSynthFromPresetURL:(NSURL *) presetURL;
- (BOOL)        createAUGraph;
- (void)        loadPresetNamed:(NSString*)name;
- (void)        configureAndStartAudioProcessingGraph: (AUGraph) graph;
- (void)        stopAudioProcessingGraph;
- (void)        restartAudioProcessingGraph;
@end


@implementation YTAppDelegate

@synthesize graphSampleRate     = _graphSampleRate;
@synthesize samplerUnit         = _samplerUnit;
@synthesize ioUnit              = _ioUnit;
@synthesize processingGraph     = _processingGraph;
-(IBAction)soundChanged:(id)sender
{
    NSString*name=[self.button titleOfSelectedItem];
    [self loadPresetNamed:name];
    [[NSUserDefaults standardUserDefaults] setObject:name forKey:@"sound"];
}
-(IBAction)openPref:(id)sender{
    SInt32 major=10,minor=0,bugFix=0;
    Gestalt(gestaltSystemVersionMajor, &major);
    Gestalt(gestaltSystemVersionMinor, &minor);
    Gestalt(gestaltSystemVersionBugFix, &bugFix);
    if(minor<9){
    NSAppleScript *a = [[NSAppleScript alloc] initWithSource:@"tell application \"System Preferences\"\nactivate\nset current pane to pane \"com.apple.preference.universalaccess\"\nactivate\nend tell"];
        [a executeAndReturnError:nil];
    }else{
        NSAppleScript *a = [[NSAppleScript alloc] initWithSource:@"tell application \"System Preferences\"\nactivate\nset current pane to pane \"com.apple.preference.security\"\nactivate\nend tell"];
        [a executeAndReturnError:nil];
    }
}
- (IBAction) playNote:(UInt32)noteNum {
    
//    UInt32 noteNum = kLowNote;
    UInt32 onVelocity = 127;
    UInt32 noteCommand = 	kMIDIMessage_NoteOn << 4 | 0;
    
    OSStatus result = noErr;
    __Require_noErr (result = MusicDeviceMIDIEvent (self.samplerUnit, noteCommand, noteNum, onVelocity, 0), logTheError);
    
logTheError:
    if (result != noErr) NSLog (@"Unable to start playing the low note. Error code: %d '%.4s'\n", (int) result, (const char *)&result);
}

- (IBAction)stopNote:(NSNumber*)note {
    
    UInt32 noteNum = [note integerValue];
    UInt32 noteCommand =    kMIDIMessage_NoteOff << 4 | 0;
    UInt32 offVelocity = 64;
    OSStatus result = noErr;
    __Require_noErr (result = MusicDeviceMIDIEvent(self.samplerUnit, noteCommand, noteNum, offVelocity, 0), logTheError);
    
logTheError:
    if (result != noErr) NSLog (@"Unable to stop playing the high note. Error code: %d '%.4s'", (int) result, (const char *)&result);
}

-(void)keyPress:(NSEvent*)event
{
  //  NSLog(@"%@",event);
    UInt32 foo=[[event characters] characterAtIndex:0];
    if(foo>200)return;
/*    if(foo>150){
        foo-=50;
    }
    if(foo<50){
        foo+=80;
    }
    if(foo<65){
        foo+=60;
    }*/
    // map from 65 to 135
    UInt32 bar=80+foo%50;
/*    NSLog(@"%d",(int)foo);
    NSLog(@"%d",(int)bar);*/
    UInt32 note=bar-(UInt32)'a'+(UInt32)55;
    [self playNote:note];
    [self performSelector:@selector(stopNote:) withObject:@(note) afterDelay:1.5];
}
- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
    [self createAUGraph];
    self.graphSampleRate = 44100.0;    // Hertz
    [self configureAndStartAudioProcessingGraph: self.processingGraph];
    NSString*name=[[NSUserDefaults standardUserDefaults] objectForKey:@"sound"];
    if(name && ![name isEqualToString:@""]){
        [self loadPresetNamed:name];
    }else{
        name=@"Vibraphone";
        [self loadPresetNamed:@"Vibraphone"];
    }
    [self.button selectItemWithTitle:name];
    [NSEvent addGlobalMonitorForEventsMatchingMask:NSKeyDownMask handler:^(NSEvent *event){
        [self keyPress: event];
        //Or just put your code here
    }];
    /*
    [NSEvent addLocalMonitorForEventsMatchingMask:NSKeyDownMask handler:^(NSEvent *event){
        [self keyPress: event];
        return event;
    }];
     */
}

// Create an audio processing graph.
- (BOOL) createAUGraph {
    
    OSStatus result = noErr;
    AUNode samplerNode, ioNode;
    
    // Specify the common portion of an audio unit's identify, used for both audio units
    // in the graph.
    AudioComponentDescription cd = {};
    cd.componentManufacturer     = kAudioUnitManufacturer_Apple;
    cd.componentFlags            = 0;
    cd.componentFlagsMask        = 0;
    
    // Instantiate an audio processing graph
    result = NewAUGraph (&_processingGraph);
    NSCAssert (result == noErr, @"Unable to create an AUGraph object. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    //Specify the Sampler unit, to be used as the first node of the graph
    cd.componentType = kAudioUnitType_MusicDevice;
    cd.componentSubType = kAudioUnitSubType_Sampler;
    
    // Add the Sampler unit node to the graph
    result = AUGraphAddNode (self.processingGraph, &cd, &samplerNode);
    NSCAssert (result == noErr, @"Unable to add the Sampler unit to the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Specify the Output unit, to be used as the second and final node of the graph
    cd.componentType = kAudioUnitType_Output;
    cd.componentSubType = kAudioUnitSubType_DefaultOutput;
    
    // Add the Output unit node to the graph
    result = AUGraphAddNode (self.processingGraph, &cd, &ioNode);
    NSCAssert (result == noErr, @"Unable to add the Output unit to the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Open the graph
    result = AUGraphOpen (self.processingGraph);
    NSCAssert (result == noErr, @"Unable to open the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Connect the Sampler unit to the output unit
    result = AUGraphConnectNodeInput (self.processingGraph, samplerNode, 0, ioNode, 0);
    NSCAssert (result == noErr, @"Unable to interconnect the nodes in the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Obtain a reference to the Sampler unit from its node
    result = AUGraphNodeInfo (self.processingGraph, samplerNode, 0, &_samplerUnit);
    NSCAssert (result == noErr, @"Unable to obtain a reference to the Sampler unit. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Obtain a reference to the I/O unit from its node
    result = AUGraphNodeInfo (self.processingGraph, ioNode, 0, &_ioUnit);
    NSCAssert (result == noErr, @"Unable to obtain a reference to the I/O unit. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    return YES;
}


// Starting with instantiated audio processing graph, configure its
// audio units, initialize it, and start it.
- (void) configureAndStartAudioProcessingGraph: (AUGraph) graph {
    
    OSStatus result = noErr;
    UInt32 framesPerSlice = 0;
    UInt32 framesPerSlicePropertySize = sizeof (framesPerSlice);
    UInt32 sampleRatePropertySize = sizeof (self.graphSampleRate);
    
    result = AudioUnitInitialize (self.ioUnit);
    NSCAssert (result == noErr, @"Unable to initialize the I/O unit. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Set the I/O unit's output sample rate.
    result =    AudioUnitSetProperty (
                                      self.ioUnit,
                                      kAudioUnitProperty_SampleRate,
                                      kAudioUnitScope_Output,
                                      0,
                                      &_graphSampleRate,
                                      sampleRatePropertySize
                                      );
    
    NSAssert (result == noErr, @"AudioUnitSetProperty (set IO unit output stream sample rate). Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Obtain the value of the maximum-frames-per-slice from the I/O unit.
    result =    AudioUnitGetProperty (
                                      self.ioUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &framesPerSlice,
                                      &framesPerSlicePropertySize
                                      );
    
    NSCAssert (result == noErr, @"Unable to retrieve the maximum frames per slice property from the I/O unit. Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Set the Sampler unit's output sample rate.
    result =    AudioUnitSetProperty (
                                      self.samplerUnit,
                                      kAudioUnitProperty_SampleRate,
                                      kAudioUnitScope_Output,
                                      0,
                                      &_graphSampleRate,
                                      sampleRatePropertySize
                                      );
    
    NSAssert (result == noErr, @"AudioUnitSetProperty (set Sampler unit output stream sample rate). Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    // Set the Sampler unit's maximum frames-per-slice.
    result =    AudioUnitSetProperty (
                                      self.samplerUnit,
                                      kAudioUnitProperty_MaximumFramesPerSlice,
                                      kAudioUnitScope_Global,
                                      0,
                                      &framesPerSlice,
                                      framesPerSlicePropertySize
                                      );
    
    NSAssert( result == noErr, @"AudioUnitSetProperty (set Sampler unit maximum frames per slice). Error code: %d '%.4s'", (int) result, (const char *)&result);
    
    
    if (graph) {
        
        // Initialize the audio processing graph.
        result = AUGraphInitialize (graph);
        NSAssert (result == noErr, @"Unable to initialze AUGraph object. Error code: %d '%.4s'", (int) result, (const char *)&result);
        
        // Start the graph
        result = AUGraphStart (graph);
        NSAssert (result == noErr, @"Unable to start audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
        
        // Print out the graph to the console
        CAShow (graph); 
    }
}

- (OSStatus) loadSynthFromPresetURL: (NSURL *) presetURL {
    
    CFDataRef propertyResourceData = 0;
    Boolean status;
    SInt32 errorCode = 0;
    OSStatus result = noErr;
    
    // Read from the URL and convert into a CFData chunk
    status = CFURLCreateDataAndPropertiesFromResource (
                                                       kCFAllocatorDefault,
                                                       (__bridge CFURLRef) presetURL,
                                                       &propertyResourceData,
                                                       NULL,
                                                       NULL,
                                                       &errorCode
                                                       );
    
    NSAssert (status == YES && propertyResourceData != 0, @"Unable to create data and properties from a preset. Error code: %d '%.4s'", (int) errorCode, (const char *)&errorCode);
    
    // Convert the data object into a property list
    CFPropertyListRef presetPropertyList = 0;
    CFPropertyListFormat dataFormat = 0;
    CFErrorRef errorRef = 0;
    presetPropertyList = CFPropertyListCreateWithData (
                                                       kCFAllocatorDefault,
                                                       propertyResourceData,
                                                       kCFPropertyListImmutable,
                                                       &dataFormat,
                                                       &errorRef
                                                       );
    
    // Set the class info property for the Sampler unit using the property list as the value.
    if (presetPropertyList != 0) {
        
        result = AudioUnitSetProperty(
                                      self.samplerUnit,
                                      kAudioUnitProperty_ClassInfo,
                                      kAudioUnitScope_Global,
                                      0,
                                      &presetPropertyList,
                                      sizeof(CFPropertyListRef)
                                      );
        
        CFRelease(presetPropertyList);
    }
    
    if (errorRef) CFRelease(errorRef);
    CFRelease (propertyResourceData);
    
    return result;
}

// Stop the audio processing graph
- (void) stopAudioProcessingGraph {
    
    OSStatus result = noErr;
    if (self.processingGraph) result = AUGraphStop(self.processingGraph);
    NSAssert (result == noErr, @"Unable to stop the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
}

// Restart the audio processing graph
- (void) restartAudioProcessingGraph {
    
    OSStatus result = noErr;
    if (self.processingGraph) result = AUGraphStart (self.processingGraph);
    NSAssert (result == noErr, @"Unable to restart the audio processing graph. Error code: %d '%.4s'", (int) result, (const char *)&result);
}

// piano sounds are taken from https://github.com/yoo16/MusicTest/blob/master/MusicTest/Piano1.aupreset
- (void)loadPresetNamed:(NSString *)name{
    NSURL *presetURL = [[NSURL alloc] initFileURLWithPath:[[NSBundle mainBundle] pathForResource:name ofType:@"aupreset"]];
    [self loadSynthFromPresetURL: presetURL];
}


@end
