//
//  SafariOmnibar.m
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

#import "SafariOmnibar.h"
#import "SparkleHelper.h"
#import "SearchProvidersEditorWindowController.h"
#import "JRSwizzle.h"

NSString * const kOmnibarSearchProviders = @"SafariOmnibar_SearchProviders";

static BOOL is_search_query(NSString *string)
{
    // Clean the input
    string = [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];

    // If it starts by a known scheme, don't try to validate the URL format, user certainly want to enter a URL.
    // Even a bad one should shouldn't be treated as a search
    if ([string hasPrefix:@"http://"] || [string hasPrefix:@"https://"] || [string hasPrefix:@"file://"]
        || [string hasPrefix:@"javascript:"] || [string hasPrefix:@"feed:"] || [string hasPrefix:@"about:"])
        return NO;

    // If more than one word, it's certainly a search query
    if ([string rangeOfString:@" "].location != NSNotFound)
        return YES;

    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"http://%@", string]];

    // A single word that can't be parsed as an URL is certainly a search query
    if (!url)
        return YES;

    // Treat localhost specifically
    if ([url.host isEqualToString:@"localhost"])
        return NO;

    // If the host part contains dot(s), treat the string as URL, the user certainly entered a URL manually with no scheme
    if ([url.host rangeOfString:@"."].location != NSNotFound)
        return NO;

    return YES;
}

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
        if (colonLoc + 2 < location.length)
        {
            searchTerms = [location substringWithRange:NSMakeRange(colonLoc + 2, location.length - (colonLoc + 2))];
        }
        else
        {
            searchTerms = @"";
        }
        [plugin resetSearchProviderForLocationField:locationField];
    }
    else if (is_search_query(location))
    {
        // If we detect a search query with not search provider keyword, use the default search provider
        searchURLTemplate = [[plugin defaultSearchProvider] objectForKey:@"SearchURLTemplate"];
    }

    if (searchURLTemplate)
    {
        searchTerms = [searchTerms stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
        // escape more
        searchTerms = [searchTerms stringByReplacingOccurrencesOfString:@"&" withString:@"%26"];
        searchTerms = [searchTerms stringByReplacingOccurrencesOfString:@"+" withString:@"%2B"];
        [locationField setStringValue:[searchURLTemplate stringByReplacingOccurrencesOfString:@"{searchTerms}" withString:searchTerms]];
        [plugin saveSearchQuery:searchTerms forLocationField:locationField];
    }

    [self SafariOmnibar_goToToolbarLocation:locationField];
}

@end

@implementation NSDocument(SO)

- (NSTextField *)SafariOmnibar_locationField
{
    id windowController = nil;
    if ([self respondsToSelector:@selector(browserWindowControllerMac)]) // Safari 5.1
    {
        windowController = [self performSelector:@selector(browserWindowControllerMac)];
    }
    else if ([self respondsToSelector:@selector(browserWindowController)]) // Safari 5.0
    {
        windowController = [self performSelector:@selector(browserWindowController)];
    }
    if (windowController)
    {
        if ([windowController respondsToSelector:@selector(locationField)])
        {
            return [windowController performSelector:@selector(locationField)];
        }
    }
    return nil;
}

- (BOOL)SafariOmnibar_restoreLastSearch:(NSTextField *)locationField forced:(BOOL)forced
{
    SafariOmnibar *plugin = [SafariOmnibar sharedInstance];

    // If current location URL contains the last search (or forced is YES), replace the URL by the search so user can easily edit it
    NSString *lastSearch = [plugin previousSearchQueryForLocationField:locationField];
    if (lastSearch
        && (forced || [[locationField.stringValue stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding] rangeOfString:lastSearch].location != NSNotFound))
    {
        NSDictionary *provider = [plugin previousSearchProviderForLocationField:locationField];
        if (provider)
        {
            // Add back the former search provider keyword
            lastSearch = [NSString stringWithFormat:@"%@ %@", [provider objectForKey:@"Keyword"], lastSearch];
            [plugin updateSearchProviderForLocationField:locationField];
        }
        if (lastSearch)
        {
            [locationField setStringValue:lastSearch];
            return YES;
        }
    }

    return NO;
}

- (void)SafariOmnibar_searchWeb:(id)sender
{
    // This is the action behind Edit > Find > Find Google...
    NSTextField *locationField = [self SafariOmnibar_locationField];
    if (locationField)
    {
        if (![self SafariOmnibar_restoreLastSearch:locationField forced:YES])
        {
            // Force default search provider
            [locationField setStringValue:@"?"];
            [[SafariOmnibar sharedInstance] updateSearchProviderForLocationField:locationField];
        }
        // Focus location field
        [locationField becomeFirstResponder];
        // Move the caret at the end of the text's field
        [(NSText *)[[locationField window] firstResponder] setSelectedRange:NSMakeRange(locationField.stringValue.length, 0)];
    }
}

- (void)SafariOmnibar_openLocation:(id)sender
{
    // This is the action behind File > Open Location...
    NSTextField *locationField = [self SafariOmnibar_locationField];
    if (locationField && ![self SafariOmnibar_restoreLastSearch:locationField forced:NO])
    {
        // Mimic Chrome behavior by selecting the content of the location text field, ready to be replaced
        [locationField selectText:nil];
    }
    [self SafariOmnibar_openLocation:sender];
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

- (NSMutableDictionary *)contextForLocationField:(NSTextField *)locationField
{
    return [locationFieldContext objectForKey:[NSNumber numberWithInteger:locationField.hash]];
}

- (void)onLocationFieldChange:(NSNotification *)notification
{
    [self updateSearchProviderForLocationField:notification.object];
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

        NSTextField *locationField = [windowController performSelector:@selector(locationField)];
        // Init Omnibar context for this field
        [locationFieldContext setObject:[NSMutableDictionary dictionary] forKey:[NSNumber numberWithInteger:locationField.hash]];

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

- (void)updateSearchProviderForLocationField:(NSTextField *)locationField
{
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
        NSDictionary *provider = nil;
        NSString *terms = nil;

        if ([location hasPrefix:@"?"])
        {
            // Force default search provider if location starts with "?"
            terms = [location substringFromIndex:1];
            provider = [[SafariOmnibar sharedInstance] defaultSearchProvider];
        }
        else
        {
            // Keyword custom search provider
            NSUInteger firstSpaceLoc = [location rangeOfString:@" "].location;

            if (firstSpaceLoc != NSNotFound && firstSpaceLoc > 0)
            {
                // Lookup for search provider keyword
                NSString *firstWord = [[location substringWithRange:NSMakeRange(0, firstSpaceLoc)] lowercaseString];
                provider = [[SafariOmnibar sharedInstance] searchProviderForKeyword:firstWord];
                if (provider)
                {
                    // Remove the keyword from terms
                    terms = [location substringFromIndex:firstSpaceLoc + 1];
                }
            }
        }

        if (provider)
        {
            // Add the provider name
            locationField.stringValue = [NSString stringWithFormat:@"%@: %@", [provider objectForKey:@"Name"], terms];
            // Save current provider for this field
            [[self contextForLocationField:locationField] setObject:provider forKey:@"provider"];
        }
    }
}

- (NSDictionary *)searchProviderForLocationField:(NSTextField *)locationField
{
    return [[self contextForLocationField:locationField] objectForKey:@"provider"];
}

- (void)resetSearchProviderForLocationField:(NSTextField *)locationField
{
    NSDictionary *lastProvider = [self searchProviderForLocationField:locationField];
    if (lastProvider)
    {
        [[self contextForLocationField:locationField] removeObjectForKey:@"provider"];
        [[self contextForLocationField:locationField] setObject:lastProvider forKey:@"last_provider"];
    }
}

- (NSDictionary *)previousSearchProviderForLocationField:(NSTextField *)locationField
{
    return [[self contextForLocationField:locationField] objectForKey:@"last_provider"];
}

- (void)saveSearchQuery:(NSString *)searchQuery forLocationField:(NSTextField *)locationField
{
    [[self contextForLocationField:locationField] setObject:searchQuery forKey:@"last_search"];
}

- (NSString *)previousSearchQueryForLocationField:(NSTextField *)locationField
{
    return [[self contextForLocationField:locationField] objectForKey:@"last_search"];
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
        locationFieldContext = [[NSMutableDictionary alloc] init];
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

        [NSClassFromString(@"BrowserDocument") jr_swizzleMethod:@selector(searchWeb:)
                                                     withMethod:@selector(SafariOmnibar_searchWeb:) error:NULL];
        [NSClassFromString(@"BrowserDocument") jr_swizzleMethod:@selector(openLocation:)
                                                     withMethod:@selector(SafariOmnibar_openLocation:) error:NULL];


        [SparkleHelper initUpdater];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [editSearchProvidersItem release], editSearchProvidersItem = nil;
    [locationFieldContext release], locationFieldContext = nil;
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
