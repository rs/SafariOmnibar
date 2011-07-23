//
//  SafariOmnibar.h
//  SafariOmnibar
//
//  Created by Olivier Poitrey on 10/07/11.
//  Copyright 2011 Olivier Poitrey. All rights reserved.
//

@interface SafariOmnibar : NSObject
{
    @private
    NSArray *searchProviders;
    NSDictionary *defaultSearchProvider;
    NSMutableDictionary *barProviderMap;
}

@property (nonatomic, readonly) NSArray *searchProviders;
@property (nonatomic, readonly) NSDictionary *defaultSearchProvider;
@property (nonatomic, readonly) NSString *pluginVersion;

+ (SafariOmnibar *)sharedInstance;
- (NSDictionary *)searchProviderForKeyword:(NSString *)keyword;
- (NSDictionary *)searchProviderForLocationField:(NSTextField *)locationField;
- (void)resetSearchProviderForLocationField:(NSTextField *)locationField;

@end
