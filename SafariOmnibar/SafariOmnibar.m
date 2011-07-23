//
//  SafariOmnibar.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

#import "SafariOmnibar.h"
#import "JRSwizzle.h"

@implementation NSObject(SO)

- (void)SafariOmnibar_showPreferences:(NSMenuItem *)menuItem
{
    [self SafariOmnibar_showPreferences:menuItem];
}

@end

@implementation NSWindowController(SO)

- (void)SafariOmnibar_goToToolbarLocation:(NSTextField *)locationField
{
    SafariOmnibar *plugin = [SafariOmnibar sharedInstance];
    NSDictionary *provider = [plugin searchProviderForLocationField:locationField];
    NSString *location = [locationField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *searchTerms = location;
    NSString *searchURLTemplate = nil;

    if (provider)
    {
        // Custom search provider
        searchURLTemplate = [provider objectForKey:@"SearchURLTemplate"];
        NSUInteger colonLoc = [location rangeOfString:@":"].location;
        searchTerms = [location substringWithRange:NSMakeRange(colonLoc + 1, location.length - (colonLoc + 1))];
        [plugin resetSearchProviderForLocationField:locationField];
    }
    else if ([location rangeOfString:@" "].location != NSNotFound // if more than one word, it's a search
             // If single word, check if it's a domain or scheme://domain or domain:port
             || ([location rangeOfString:@"."].location == NSNotFound && [location rangeOfString:@":"].location == NSNotFound))
    {
        // Default search provider
        searchURLTemplate = [[plugin defaultSearchProvider] objectForKey:@"SearchURLTemplate"];
    }
    else
    {
        // Not a search, URL?
    }

    if (searchURLTemplate)
    {
        [locationField setStringValue:[searchURLTemplate stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:searchTerms]];
    }

    [self SafariOmnibar_goToToolbarLocation:locationField];
}

@end

@implementation SafariOmnibar
@synthesize defaultSearchProvider;

- (void)onLocationFieldChange:(NSNotification *)notification
{
    NSTextField *locationField = notification.object;
    NSString *location = locationField.stringValue;
    NSDictionary *provider = [self searchProviderForLocationField:locationField];

    if (provider)
    {
        NSString *providerName = [provider objectForKey:@"Name"];
        if (![location hasPrefix:[NSString stringWithFormat:@"%@: ", providerName]])
        {
            [self resetSearchProviderForLocationField:locationField];
            NSUInteger colonLoc = [location rangeOfString:@":"].location;
            if (colonLoc != NSNotFound)
            {
                location = [NSString stringWithFormat:@"%@%@",
                            [provider objectForKey:@"Keyword"],
                            [location substringWithRange:NSMakeRange(colonLoc + 1, location.length - (colonLoc + 1))]];
                [locationField setStringValue:location];
            }
        }
    }
    else
    {
        NSUInteger firstSpaceLoc = [location rangeOfString:@" "].location;
        if (firstSpaceLoc != NSNotFound && firstSpaceLoc > 0)
        {
            // Lookup for search provider keyword
            NSString *firstWord = [[location substringWithRange:NSMakeRange(0, firstSpaceLoc)] lowercaseString];
            NSDictionary *provider = [[SafariOmnibar sharedInstance] searchProviderForKeyword:firstWord];
            if (provider)
            {
                NSString *terms = [location substringWithRange:NSMakeRange(firstSpaceLoc + 1, location.length - (firstSpaceLoc + 1))];
                locationField.stringValue = [NSString stringWithFormat:@"%@: %@", [provider objectForKey:@"Name"], terms];
                [barProviderMap setObject:provider forKey:[NSNumber numberWithInteger:locationField.hash]];
            }
        }
    }
}

- (void)initBrowserWindow:(NSWindow *)window
{
    NSWindowController *windowController = [window windowController];
    if ([windowController respondsToSelector:@selector(searchField)]
        && [windowController respondsToSelector:@selector(locationField)])
    {
        [[windowController performSelector:@selector(searchField)] removeFromSuperview];

        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onLocationFieldChange:)
                                                     name:@"NSControlTextDidChangeNotification"
                                                   object:[windowController performSelector:@selector(locationField)]];
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

- (NSDictionary *)searchProviderForLocationField:(NSTextField *)locationField
{
    return [barProviderMap objectForKey:[NSNumber numberWithInteger:locationField.hash]];
}

- (void)resetSearchProviderForLocationField:(NSTextField *)locationField
{
    [barProviderMap removeObjectForKey:[NSNumber numberWithInteger:locationField.hash]];
}

- (id)init
{
    if ((self = [super init]))
    {
        barProviderMap = [[NSMutableDictionary alloc] init];
        [self loadSearchProviders];

        for (NSWindow *window in [[NSApplication sharedApplication] windows])
        {
            [self initBrowserWindow:window];
        }

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(onNewWindow:) name:@"NSWindowDidBecomeMainNotification" object:nil];

        if (NSClassFromString(@"BrowserWindowControllerMac"))
        {
            // Safari 5.1
            [NSClassFromString(@"BrowserWindowControllerMac") jr_swizzleMethod:@selector(goToToolbarLocation:)
                                                                    withMethod:@selector(SafariOmnibar_goToToolbarLocation:) error:NULL];
        }
        else
        {
            // Safari 5.0
            [NSClassFromString(@"BrowserWindowController") jr_swizzleMethod:@selector(goToToolbarLocation:)
                                                                 withMethod:@selector(SafariOmnibar_goToToolbarLocation:) error:NULL];
        }

    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [barProviderMap release], barProviderMap = nil;
    [defaultSearchProvider release], defaultSearchProvider = nil;
    [searchProviders release], searchProviders = nil;
    [super dealloc];
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
    [self sharedInstance];
    NSLog(@"Safari Omnibar Loaded");
}

@end
