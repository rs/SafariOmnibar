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
}

@property (nonatomic, readonly) NSDictionary *defaultSearchProvider;

+ (SafariOmnibar *)sharedInstance;
- (NSDictionary *)searchProviderForKeyword:(NSString *)keyword;

@end
