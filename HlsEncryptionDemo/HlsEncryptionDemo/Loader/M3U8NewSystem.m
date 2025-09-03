//
//  M3U8NewSystem.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8NewSystem.h"
#import "CacheConfig.h"
#import "CacheManager.h"

@implementation M3U8NewSystem

+ (NSString *)version {
    return @"2.0.0";
}

+ (NSDictionary *)systemInfo {
    CacheConfig *cacheConfig = [CacheConfig sharedConfig];
    CacheStatistics *cacheStats = [[CacheManager sharedManager] statistics];
    
    return @{
        @"version": [self version],
        @"buildDate": @"2024-12-19",
        @"components": @[
            @"M3U8Models",
            @"CacheManager", 
            @"M3U8Parser",
            @"QualitySelector",
            @"M3U8PlayerManager"
        ],
        @"cacheConfig": @{
            @"maxFileCount": @(cacheConfig.maxFileCount),
            @"maxMemorySize": @(cacheConfig.maxMemorySize),
            @"cacheDirectory": cacheConfig.cacheDirectory,
            @"expirationMinutes": @(cacheConfig.cacheExpirationMinutes)
        },
        @"cacheStatistics": @{
            @"fileCount": @(cacheStats.fileCount),
            @"totalSize": @(cacheStats.totalSize),
            @"hitCount": @(cacheStats.hitCount),
            @"missCount": @(cacheStats.missCount),
            @"hitRate": @(cacheStats.hitRate)
        }
    };
}

@end
