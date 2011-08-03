//
//  SparkleHelper.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 02/08/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

#import "SparkleHelper.h"

@implementation SparkleHelper

+ (void)initUpdater
{
    if (self != SparkleHelper.class) return;
    
    Class SUUpdater_class = NSClassFromString(@"SUUpdater");
    if (SUUpdater_class == Nil)
    {
        // Only load Sparkle if another bundle hasn't yet (i.e. WebKit or other SIMBL plugins)
		// Loading different versions of a framework is a Bad Idea
        NSString *sparklePath = [[[NSBundle bundleForClass:self] bundlePath] stringByAppendingString:@"/Contents/Frameworks/Sparkle.framework"];
        [[NSBundle bundleWithPath:sparklePath] load];
        SUUpdater_class = NSClassFromString(@"SUUpdater");
    }
    
    id updater = nil;
    if ([SUUpdater_class respondsToSelector:@selector(updaterForBundle:)])
    {
        updater = [SUUpdater_class performSelector:@selector(updaterForBundle:) withObject:[NSBundle bundleForClass:self]];
    }
    
    if (updater)
    {
        [updater setDelegate:self];
        if ([updater respondsToSelector:@selector(applicationDidFinishLaunching:)])
        {
            [updater performSelector:@selector(applicationDidFinishLaunching:) withObject:nil];
        }
        if ([updater respondsToSelector:@selector(resetUpdateCycle)])
        {
            [updater performSelector:@selector(resetUpdateCycle) withObject:nil];
        }
    }
}

+ (NSString *)pathToRelaunchForUpdater:(id)updater
{
	return [[NSBundle mainBundle] bundlePath];
}

@end
