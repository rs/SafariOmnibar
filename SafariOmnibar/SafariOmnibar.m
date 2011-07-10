//
//  SafariOmnibar.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Dailymotion. All rights reserved.
//

#import "SafariOmnibar.h"
#import "JRSwizzle.h"

@implementation NSWindowController(SO)

- (void)SafariOmnibar_goToToolbarLocation:(NSTextField *)locationField
{
    NSString *location = [locationField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if ([location rangeOfString:@" "].location != NSNotFound || [location rangeOfString:@"."].location == NSNotFound)
    {
        [locationField setStringValue:[@"http://www.google.com/search?q=" stringByAppendingString:location]];
    }
    [self SafariOmnibar_goToToolbarLocation:locationField];
}

@end

@implementation SafariOmnibar

- (void)initBrowserWindow:(NSWindow *)window
{
    NSWindowController *windowController = [window windowController];
    if ([windowController respondsToSelector:@selector(searchField)])
    {
        [[windowController performSelector:@selector(searchField)] removeFromSuperview];
    }
}

- (void)onNewWindow:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    [self initBrowserWindow:window];
}

+ (SafariOmnibar *)sharedInstance
{
    static SafariOmnibar *plugin = nil;
    
    if (plugin == nil)
        plugin = [[SafariOmnibar alloc] init];
    
    return plugin;
}

+ (void)load
{
    NSLog(@"Safari Omnibar Loaded");
    SafariOmnibar *plugin = [self sharedInstance];

    for (NSWindow *window in [[NSApplication sharedApplication] windows])
    {
        [plugin initBrowserWindow:window];
    }

    [[NSNotificationCenter defaultCenter] addObserver:[self sharedInstance]
                                             selector:@selector(onNewWindow:)
                                                 name:@"NSWindowDidBecomeMainNotification"
                                               object:nil];

    [NSClassFromString(@"BrowserWindowControllerMac") jr_swizzleMethod:@selector(goToToolbarLocation:) withMethod:@selector(SafariOmnibar_goToToolbarLocation:) error:NULL];
}

@end
