//
//  CacheConfig.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "CacheConfig.h"

@implementation CacheConfig

+ (instancetype)sharedConfig {
    static CacheConfig *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CacheConfig alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 设置默认配置参数
        _cacheDirectory = @"Documents/M3U8Cache";
        _maxFileCount = 1000;
        _maxMemorySize = 20; // 20MB
        _cacheExpirationMinutes = 60; // 60分钟
    }
    return self;
}

- (NSString *)fullCacheDirectoryPath {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths firstObject];
    NSString *cacheDir = [self.cacheDirectory stringByReplacingOccurrencesOfString:@"Documents/" withString:@""];
    return [documentsDirectory stringByAppendingPathComponent:cacheDir];
}

- (NSUInteger)maxMemorySizeInBytes {
    return self.maxMemorySize * 1024 * 1024; // 转换为字节
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CacheConfig: directory=%@, maxFiles=%ld, maxMemory=%ldMB, expiration=%ldmin", 
            [self fullCacheDirectoryPath], (long)self.maxFileCount, (long)self.maxMemorySize, (long)self.cacheExpirationMinutes];
}

@end
