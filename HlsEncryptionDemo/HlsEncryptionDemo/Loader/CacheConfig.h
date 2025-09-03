//
//  CacheConfig.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 缓存配置类
 * 静态配置类，包含所有缓存相关的默认参数
 */
@interface CacheConfig : NSObject

/**
 * 获取共享配置实例
 */
+ (instancetype)sharedConfig;

/**
 * 缓存目录路径（默认：Documents/M3U8Cache/）
 */
@property (nonatomic, readonly) NSString *cacheDirectory;

/**
 * 最大文件数限制（默认：1000）
 */
@property (nonatomic, readonly) NSInteger maxFileCount;

/**
 * 最大内存占用限制（默认：20MB）
 */
@property (nonatomic, readonly) NSInteger maxMemorySize;

/**
 * 缓存有效期设置（默认：60分钟）
 */
@property (nonatomic, readonly) NSInteger cacheExpirationMinutes;

/**
 * 获取完整的缓存目录路径
 */
- (NSString *)fullCacheDirectoryPath;

/**
 * 获取最大内存大小（字节）
 */
- (NSUInteger)maxMemorySizeInBytes;

@end

NS_ASSUME_NONNULL_END
