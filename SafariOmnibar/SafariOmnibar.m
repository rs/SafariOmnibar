//
//  SafariOmnibar.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

#import "SafariOmnibar.h"
#import "JRSwizzle.h"

@implementation NSWindowController(SO)

- (void)SafariOmnibar_goToToolbarLocation:(NSTextField *)locationField
{
    NSString *location = [locationField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    NSUInteger firstSpaceLoc = [location rangeOfString:@" "].location;
    if (firstSpaceLoc != NSNotFound || [location rangeOfString:@"."].location == NSNotFound)
    {
        NSString *searchTerms = location;
        NSString *searchURLTemplate = nil;

        if (firstSpaceLoc != NSNotFound)
        {
            // Lookup for search provider keyword
            NSString *firstWord = [[location substringWithRange:NSMakeRange(0, firstSpaceLoc)] lowercaseString];
            NSDictionary *provider = [[SafariOmnibar sharedInstance] searchProviderForKeyword:firstWord];
            if (provider)
            {
                searchURLTemplate = [provider objectForKey:@"SearchURLTemplate"];
                // Remove the keyword from search
                searchTerms = [location substringWithRange:NSMakeRange(firstSpaceLoc + 1, location.length - (firstSpaceLoc + 1))];
            }
        }

        if (!searchURLTemplate)
        {
            searchURLTemplate = [[[SafariOmnibar sharedInstance] defaultSearchProvider] objectForKey:@"SearchURLTemplate"];
        }

        if (searchURLTemplate)
        {
            [locationField setStringValue:[searchURLTemplate stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:searchTerms]];
        }
    }
    [self SafariOmnibar_goToToolbarLocation:locationField];
}

@end

@implementation SafariOmnibar
@synthesize defaultSearchProvider;

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

- (void)loadSearchProviders
{
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"SearchProviders" ofType:@"plist"];
    NSDictionary *searchProvidersConf = [NSDictionary dictionaryWithContentsOfFile:path];

    [searchProviders release]; searchProviders = nil;
    [defaultSearchProvider release]; defaultSearchProvider = nil;

    searchProviders = [[searchProvidersConf objectForKey:@"SearchProvidersList"] retain];

    for (NSDictionary *searchProvider in searchProviders)
    {
        if ([[searchProvider objectForKey:@"Default"] boolValue])
        {
            defaultSearchProvider = [searchProvider retain];
            break;
        }
    }
}

- (NSDictionary *)searchProviderForKeyword:(NSString *)keyword
{
    NSString *lcKeyword = [keyword lowercaseString];
    for (NSDictionary *provider in searchProviders)
    {
        if ([lcKeyword isEqualToString:[[provider objectForKey:@"Keyword"] lowercaseString]])
        {
            return provider;
        }
    }

    return nil;
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

    [plugin loadSearchProviders];

    for (NSWindow *window in [[NSApplication sharedApplication] windows])
    {
        [plugin initBrowserWindow:window];
    }
    
    [[NSNotificationCenter defaultCenter] addObserver:[self sharedInstance]
                                             selector:@selector(onNewWindow:)
                                                 name:@"NSWindowDidBecomeMainNotification"
                                               object:nil];

    if (NSClassFromString(@"BrowserWindowControllerMac"))
    {
        [NSClassFromString(@"BrowserWindowControllerMac") jr_swizzleMethod:@selector(goToToolbarLocation:)
                                                                withMethod:@selector(SafariOmnibar_goToToolbarLocation:) error:NULL];
    }
    else
    {
        [NSClassFromString(@"BrowserWindowController") jr_swizzleMethod:@selector(goToToolbarLocation:)
                                                             withMethod:@selector(SafariOmnibar_goToToolbarLocation:) error:NULL];
    }
}

@end
