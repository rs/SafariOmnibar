//
//  SearchProvidersEditorWindowController.h
//  SafariOmnibar
//
//  Created by Nolan Waite on 11-07-23.
//

#import <Cocoa/Cocoa.h>

@interface SearchProvidersEditorWindowController : NSWindowController
{
    NSMutableArray *searchProviders;
}

@property (nonatomic, readonly, copy) NSMutableArray *searchProviders;
@property (nonatomic, retain) IBOutlet NSArrayController *arrayController;
@property (nonatomic, retain) IBOutlet NSTableView *tableView;

- (id)initWithSearchProviders:(NSArray *)searchProviders;

- (IBAction)addSearchProvider:(id)sender;
- (IBAction)removeSearchProvider:(id)sender;
- (IBAction)setSelectedProviderAsDefault:(id)sender;
- (IBAction)dismiss:(id)sender;

@end
