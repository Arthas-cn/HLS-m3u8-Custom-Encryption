//
//  CacheManager.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 缓存统计信息
 */
@interface CacheStatistics : NSObject
@property (nonatomic, assign) NSInteger fileCount;         // 文件数量
@property (nonatomic, assign) NSUInteger totalSize;        // 总占用空间（字节）
@property (nonatomic, assign) NSInteger hitCount;          // 命中次数
@property (nonatomic, assign) NSInteger missCount;         // 未命中次数
@property (nonatomic, assign, readonly) CGFloat hitRate;   // 命中率
@end

/**
 * 缓存管理器
 * 实现磁盘缓存、LRU淘汰策略、线程安全
 */
@interface CacheManager : NSObject

/**
 * 获取共享缓存管理器实例
 */
+ (instancetype)sharedManager;

/**
 * 根据URL和Token获取缓存的M3U8内容
 * @param url M3U8文件URL
 * @param token 授权token
 * @return 缓存的内容，如果不存在或已过期返回nil
 */
- (NSData * _Nullable)cachedDataForURL:(NSString *)url token:(NSString *)token;

/**
 * 缓存M3U8文件内容
 * @param data 文件内容
 * @param url M3U8文件URL
 * @param token 授权token
 */
- (void)cacheData:(NSData *)data forURL:(NSString *)url token:(NSString *)token;

/**
 * 检查缓存是否存在且有效
 * @param url M3U8文件URL
 * @param token 授权token
 * @return YES如果存在且有效，否则NO
 */
- (BOOL)isCacheValidForURL:(NSString *)url token:(NSString *)token;

/**
 * 清理过期的缓存文件
 */
- (void)cleanExpiredCache;

/**
 * 清理所有缓存
 */
- (void)clearAllCache;

/**
 * 获取缓存统计信息
 */
- (CacheStatistics *)statistics;

/**
 * 手动触发LRU清理（当超过配置限制时）
 */
- (void)performLRUCleanupIfNeeded;

@end

NS_ASSUME_NONNULL_END
