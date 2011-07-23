//
//  SearchProvidersEditorWindowController.m
//  SafariOmnibar
//
//  Created by Nolan Waite on 11-07-23.
//

#import "SearchProvidersEditorWindowController.h"

@implementation SearchProvidersEditorWindowController

@synthesize searchProviders;
@synthesize arrayController;
@synthesize tableView;

- (id)initWithSearchProviders:(NSArray *)someSearchProviders
{
    if ((self = [super initWithWindowNibName:@"SearchProvidersEditor"]))
    {
        searchProviders = [someSearchProviders mutableCopy];
    }
    return self;
}

static NSString *FirstHTTPURLStringOnGeneralPasteboard()
{
    NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
    NSArray *copiedStrings = [generalPasteboard readObjectsForClasses:[NSArray arrayWithObject:[NSString class]] options:nil];
    for (NSString *maybeURLString in copiedStrings)
    {
        if ([maybeURLString hasPrefix:@"http"]) return maybeURLString;
    }
    return nil;
}

- (IBAction)addSearchProvider:(id)sender
{
    NSMutableDictionary *newProvider = [NSMutableDictionary dictionaryWithObjectsAndKeys:@"New Provider", @"Name", @"new", @"Keyword", @"http://example.com/search?q={searchTerms}", @"SearchURLTemplate", nil];
    NSString *copiedURLString = FirstHTTPURLStringOnGeneralPasteboard();
    if (copiedURLString != nil)
    {
        [newProvider setObject:copiedURLString forKey:@"SearchURLTemplate"];
    }
    [self.arrayController addObject:newProvider];
    [self.tableView editColumn:0 row:([self.searchProviders count] - 1) withEvent:nil select:YES];
}

- (IBAction)removeSearchProvider:(id)sender
{
    if ([self.searchProviders count] < 2) return;
    BOOL wasDefault = [[self.arrayController.selection valueForKey:@"Default"] boolValue];
    [self.arrayController removeObjects:self.arrayController.selectedObjects];
    if (wasDefault)
    {
        [self setSelectedProviderAsDefault:nil];
    }
}

- (IBAction)setSelectedProviderAsDefault:(id)sender
{
    [self.arrayController.arrangedObjects setValue:[NSNumber numberWithBool:NO] forKey:@"Default"];
    [self.arrayController.selectedObjects setValue:[NSNumber numberWithBool:YES] forKey:@"Default"];
}

- (IBAction)dismiss:(id)sender
{
    [[NSApplication sharedApplication] endSheet:self.window];
}

- (void)dealloc
{
    [tableView release], tableView = nil;
    [arrayController release], arrayController = nil;
    [searchProviders release], searchProviders = nil;
    [super dealloc];
}

@end
