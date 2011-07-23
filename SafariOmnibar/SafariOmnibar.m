//
//  SafariOmnibar.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

#import "SafariOmnibar.h"
#import "SearchProvidersEditorWindowController.h"
#import "JRSwizzle.h"

NSString * const kOmnibarSearchProviders = @"SafariOmnibar_SearchProviders";

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
    NSString *location = locationField.stringValue;
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
        searchTerms = [searchTerms stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        [locationField setStringValue:[searchURLTemplate stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:searchTerms]];
    }

    [self SafariOmnibar_goToToolbarLocation:locationField];
}

@end

@interface SafariOmnibar ()

@property (nonatomic, retain) NSMenuItem *editSearchProvidersItem;

@end

@implementation SafariOmnibar
@synthesize searchProviders;
@synthesize defaultSearchProvider;
@synthesize editSearchProvidersItem;
@dynamic pluginVersion;

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

- (void)addContextMenuItemsToLocationField:(id)locationField
{
    // To add an item to the location field's context menu, we need to add one
    // to its field editor. In Safari, this field editor appears to be unique
    // to the location field, and the same instance is shared throughout the
    // application. This lets us simply keep a reference to the menu item we
    // add and check its presence to stop from adding the menu item multiple
    // times.
    if (self.editSearchProvidersItem) return;
    self.editSearchProvidersItem = [[[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Edit Omnibar Search Providers…", @"location field context menu item")
                                                               action:@selector(editSearchProviders:)
                                                        keyEquivalent:@""] autorelease];
    self.editSearchProvidersItem.target = self;
    NSWindow *window = [locationField performSelector:@selector(window)];
    NSResponder *locationFieldEditor = [window fieldEditor:YES forObject:locationField];
    [locationFieldEditor.menu addItem:[NSMenuItem separatorItem]];
    [locationFieldEditor.menu addItem:self.editSearchProvidersItem];
}

- (void)initBrowserWindow:(NSWindow *)window
{
    NSWindowController *windowController = [window windowController];
    if ([windowController respondsToSelector:@selector(searchField)]
        && [windowController respondsToSelector:@selector(locationField)])
    {
        [[windowController performSelector:@selector(searchField)] removeFromSuperview];

        id locationField = [windowController performSelector:@selector(locationField)];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(onLocationFieldChange:)
                                                     name:@"NSControlTextDidChangeNotification"
                                                   object:locationField];
        [self addContextMenuItemsToLocationField:locationField];
    }
}

- (void)onNewWindow:(NSNotification *)notification
{
    NSWindow *window = notification.object;
    [self initBrowserWindow:window];
}

- (void)loadApplicationDefaults
{
    NSString *path = [[NSBundle bundleForClass:self.class] pathForResource:@"SearchProviders" ofType:@"plist"];
    NSDictionary *searchProvidersConf = [NSDictionary dictionaryWithContentsOfFile:path];
    NSArray *defaultSearchProviders = [searchProvidersConf objectForKey:@"SearchProvidersList"];
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObject:defaultSearchProviders
                                                            forKey:kOmnibarSearchProviders];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
}

- (void)loadSearchProviders
{
    [searchProviders release]; searchProviders = nil;
    [defaultSearchProvider release]; defaultSearchProvider = nil;

    searchProviders = [[[NSUserDefaults standardUserDefaults] arrayForKey:kOmnibarSearchProviders] retain];

    for (NSDictionary *searchProvider in searchProviders)
    {
        if ([[searchProvider objectForKey:@"Default"] boolValue])
        {
            defaultSearchProvider = [searchProvider retain];
            break;
        }
    }
}

- (void)saveSearchProviders:(NSArray *)someSearchProviders
{
    [[NSUserDefaults standardUserDefaults] setObject:someSearchProviders
                                              forKey:kOmnibarSearchProviders];
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

- (void)editSearchProviders:(id)sender
{
    NSMutableArray *mutableSearchProviders = [NSMutableArray array];
    for (NSDictionary *provider in [SafariOmnibar sharedInstance].searchProviders)
    {
        [mutableSearchProviders addObject:[[provider mutableCopy] autorelease]];
    }
    SearchProvidersEditorWindowController *editor = [[SearchProvidersEditorWindowController alloc] initWithSearchProviders:mutableSearchProviders];
    [[NSApplication sharedApplication] beginSheet:editor.window
                                   modalForWindow:[[NSApplication sharedApplication] keyWindow]
                                    modalDelegate:self
                                   didEndSelector:@selector(didEndSheet:returnCode:contextInfo:)
                                      contextInfo:editor];
}

- (void)didEndSheet:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
    SearchProvidersEditorWindowController *editor = contextInfo;
    [self saveSearchProviders:editor.searchProviders];
    [self loadSearchProviders];
    [sheet orderOut:self];
    [editor autorelease];
}

- (id)init
{
    if ((self = [super init]))
    {
        barProviderMap = [[NSMutableDictionary alloc] init];
        [self loadApplicationDefaults];
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
    [editSearchProvidersItem release], editSearchProvidersItem = nil;
    [barProviderMap release], barProviderMap = nil;
    [defaultSearchProvider release], defaultSearchProvider = nil;
    [searchProviders release], searchProviders = nil;
    [super dealloc];
}

+ (NSString *)pluginVersion
{
    return [[[NSBundle bundleForClass:self] infoDictionary] objectForKey:@"CFBundleVersion"];
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
    NSLog(@"Safari Omnibar %@ Loaded", self.pluginVersion);
}

@end
