//
//  CacheManager.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "CacheManager.h"
#import "CacheConfig.h"
#import <CommonCrypto/CommonDigest.h>

// MARK: - CacheStatistics Implementation
@implementation CacheStatistics

- (CGFloat)hitRate {
    NSInteger totalRequests = self.hitCount + self.missCount;
    if (totalRequests == 0) return 0.0f;
    return (CGFloat)self.hitCount / totalRequests;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"CacheStats: files=%ld, size=%.2fMB, hits=%ld, misses=%ld, hitRate=%.1f%%", 
            (long)self.fileCount, self.totalSize / (1024.0 * 1024.0), 
            (long)self.hitCount, (long)self.missCount, self.hitRate * 100];
}

@end

// MARK: - Cache Item (Internal)
@interface CacheItem : NSObject
@property (nonatomic, strong) NSString *key;
@property (nonatomic, strong) NSString *filePath;
@property (nonatomic, strong) NSDate *createTime;
@property (nonatomic, strong) NSDate *lastAccessTime;
@property (nonatomic, assign) NSUInteger fileSize;
@end

@implementation CacheItem
@end

// MARK: - CacheManager Implementation
@interface CacheManager ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, CacheItem *> *cacheIndex;
@property (nonatomic, strong) dispatch_queue_t cacheQueue;
@property (nonatomic, strong) CacheStatistics *stats;
@property (nonatomic, strong) NSFileManager *fileManager;
@end

@implementation CacheManager

+ (instancetype)sharedManager {
    static CacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[CacheManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheIndex = [[NSMutableDictionary alloc] init];
        _cacheQueue = dispatch_queue_create("com.hlsencryption.cache", DISPATCH_QUEUE_CONCURRENT);
        _stats = [[CacheStatistics alloc] init];
        _fileManager = [NSFileManager defaultManager];
        
        [self setupCacheDirectory];
        [self loadCacheIndex];
    }
    return self;
}

#pragma mark - Public Methods

- (NSData *)cachedDataForURL:(NSString *)url token:(NSString *)token {
    __block NSData *result = nil;
    
    dispatch_sync(self.cacheQueue, ^{
        NSString *cacheKey = [self cacheKeyForURL:url token:token];
        CacheItem *item = self.cacheIndex[cacheKey];
        
        if (item && [self isCacheItemValid:item]) {
            // 更新访问时间
            item.lastAccessTime = [NSDate date];
            
            // 读取文件内容
            result = [NSData dataWithContentsOfFile:item.filePath];
            if (result) {
                self.stats.hitCount++;
                NSLog(@"[CacheManager] 缓存命中: %@", cacheKey);
            } else {
                // 文件丢失，清理索引
                [self removeCacheItem:item];
                self.stats.missCount++;
                NSLog(@"[CacheManager] 缓存文件丢失: %@", cacheKey);
            }
        } else {
            self.stats.missCount++;
            if (item && ![self isCacheItemValid:item]) {
                NSLog(@"[CacheManager] 缓存已过期: %@", cacheKey);
                [self removeCacheItem:item];
            } else {
                NSLog(@"[CacheManager] 缓存未命中: %@", cacheKey);
            }
        }
    });
    
    return result;
}

- (void)cacheData:(NSData *)data forURL:(NSString *)url token:(NSString *)token {
    dispatch_barrier_async(self.cacheQueue, ^{
        NSString *cacheKey = [self cacheKeyForURL:url token:token];
        NSString *filePath = [self filePathForCacheKey:cacheKey];
        
        // 写入文件
        BOOL success = [data writeToFile:filePath atomically:YES];
        if (success) {
            // 创建缓存项
            CacheItem *item = [[CacheItem alloc] init];
            item.key = cacheKey;
            item.filePath = filePath;
            item.createTime = [NSDate date];
            item.lastAccessTime = [NSDate date];
            item.fileSize = data.length;
            
            // 更新索引
            CacheItem *oldItem = self.cacheIndex[cacheKey];
            if (oldItem) {
                [self removeCacheItem:oldItem];
            }
            self.cacheIndex[cacheKey] = item;
            
            // 更新统计信息
            [self updateStatistics];
            
            NSLog(@"[CacheManager] 缓存写入成功: %@, size=%lu", cacheKey, (unsigned long)data.length);
            
            // 检查是否需要LRU清理
            [self performLRUCleanupIfNeeded];
        } else {
            NSLog(@"[CacheManager] 缓存写入失败: %@", cacheKey);
        }
    });
}

- (BOOL)isCacheValidForURL:(NSString *)url token:(NSString *)token {
    __block BOOL isValid = NO;
    
    dispatch_sync(self.cacheQueue, ^{
        NSString *cacheKey = [self cacheKeyForURL:url token:token];
        CacheItem *item = self.cacheIndex[cacheKey];
        isValid = (item != nil && [self isCacheItemValid:item]);
    });
    
    return isValid;
}

- (void)cleanExpiredCache {
    dispatch_barrier_async(self.cacheQueue, ^{
        NSMutableArray *expiredItems = [[NSMutableArray alloc] init];
        
        for (CacheItem *item in self.cacheIndex.allValues) {
            if (![self isCacheItemValid:item]) {
                [expiredItems addObject:item];
            }
        }
        
        for (CacheItem *item in expiredItems) {
            [self removeCacheItem:item];
        }
        
        [self updateStatistics];
        NSLog(@"[CacheManager] 清理过期缓存完成，清理了%lu个文件", (unsigned long)expiredItems.count);
    });
}

- (void)clearAllCache {
    dispatch_barrier_async(self.cacheQueue, ^{
        // 删除所有缓存文件
        for (CacheItem *item in self.cacheIndex.allValues) {
            [self.fileManager removeItemAtPath:item.filePath error:nil];
        }
        
        // 清空索引
        [self.cacheIndex removeAllObjects];
        
        // 重置统计信息
        self.stats = [[CacheStatistics alloc] init];
        
        NSLog(@"[CacheManager] 清空所有缓存完成");
    });
}


- (CacheStatistics *)statistics {
    static dispatch_once_t onceToken;
    static CacheStatistics *instance = nil;
    dispatch_once(&onceToken, ^{
        instance = [CacheStatistics new];
    });
    return instance;
}

- (void)performLRUCleanupIfNeeded {
    CacheConfig *config = [CacheConfig sharedConfig];
    
    // 检查文件数量限制
    if (self.cacheIndex.count > config.maxFileCount) {
        NSInteger toRemove = self.cacheIndex.count - config.maxFileCount;
        [self performLRUCleanup:toRemove];
    }
    
    // 检查内存大小限制
    NSUInteger totalSize = 0;
    for (CacheItem *item in self.cacheIndex.allValues) {
        totalSize += item.fileSize;
    }
    
    if (totalSize > [config maxMemorySizeInBytes]) {
        // 需要清理到80%的限制
        NSUInteger targetSize = [config maxMemorySizeInBytes] * 0.8;
        [self performLRUCleanupToSize:targetSize];
    }
}

#pragma mark - Private Methods

- (void)setupCacheDirectory {
    CacheConfig *config = [CacheConfig sharedConfig];
    NSString *cacheDir = [config fullCacheDirectoryPath];
    
    if (![self.fileManager fileExistsAtPath:cacheDir]) {
        NSError *error;
        BOOL success = [self.fileManager createDirectoryAtPath:cacheDir 
                                   withIntermediateDirectories:YES 
                                                    attributes:nil 
                                                         error:&error];
        if (!success) {
            NSLog(@"[CacheManager] 创建缓存目录失败: %@", error.localizedDescription);
        } else {
            NSLog(@"[CacheManager] 缓存目录创建成功: %@", cacheDir);
        }
    }
}

- (void)loadCacheIndex {
    // 从缓存目录加载已有的缓存文件信息
    CacheConfig *config = [CacheConfig sharedConfig];
    NSString *cacheDir = [config fullCacheDirectoryPath];
    
    NSError *error;
    NSArray *files = [self.fileManager contentsOfDirectoryAtPath:cacheDir error:&error];
    
    if (files) {
        for (NSString *fileName in files) {
            if ([fileName hasSuffix:@".m3u8"]) {
                NSString *filePath = [cacheDir stringByAppendingPathComponent:fileName];
                NSString *cacheKey = [fileName stringByDeletingPathExtension];
                
                NSDictionary *attributes = [self.fileManager attributesOfItemAtPath:filePath error:nil];
                if (attributes) {
                    CacheItem *item = [[CacheItem alloc] init];
                    item.key = cacheKey;
                    item.filePath = filePath;
                    item.createTime = attributes[NSFileCreationDate];
                    item.lastAccessTime = attributes[NSFileModificationDate];
                    item.fileSize = [attributes[NSFileSize] unsignedIntegerValue];
                    
                    if ([self isCacheItemValid:item]) {
                        self.cacheIndex[cacheKey] = item;
                    } else {
                        // 过期文件，删除
                        [self.fileManager removeItemAtPath:filePath error:nil];
                    }
                }
            }
        }
        
        [self updateStatistics];
        NSLog(@"[CacheManager] 加载缓存索引完成，共%lu个有效文件", (unsigned long)self.cacheIndex.count);
    }
}

- (NSString *)cacheKeyForURL:(NSString *)url token:(NSString *)token {
    NSString *combined = [NSString stringWithFormat:@"%@%@", url, token];
    return [self md5Hash:combined];
}

- (NSString *)md5Hash:(NSString *)input {
    const char *cStr = [input UTF8String];
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(cStr, (CC_LONG)strlen(cStr), digest);
    
    NSMutableString *output = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [output appendFormat:@"%02x", digest[i]];
    }
    
    return output;
}

- (NSString *)filePathForCacheKey:(NSString *)cacheKey {
    CacheConfig *config = [CacheConfig sharedConfig];
    NSString *cacheDir = [config fullCacheDirectoryPath];
    NSString *fileName = [NSString stringWithFormat:@"%@.m3u8", cacheKey];
    return [cacheDir stringByAppendingPathComponent:fileName];
}

- (BOOL)isCacheItemValid:(CacheItem *)item {
    CacheConfig *config = [CacheConfig sharedConfig];
    NSTimeInterval expirationInterval = config.cacheExpirationMinutes * 60; // 转换为秒
    NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:item.createTime];
    return age < expirationInterval;
}

- (void)removeCacheItem:(CacheItem *)item {
    [self.fileManager removeItemAtPath:item.filePath error:nil];
    [self.cacheIndex removeObjectForKey:item.key];
}

- (void)updateStatistics {
    self.stats.fileCount = self.cacheIndex.count;
    
    NSUInteger totalSize = 0;
    for (CacheItem *item in self.cacheIndex.allValues) {
        totalSize += item.fileSize;
    }
    self.stats.totalSize = totalSize;
}

- (void)performLRUCleanup:(NSInteger)count {
    // 按最后访问时间排序，最久未访问的排在前面
    NSArray *sortedItems = [self.cacheIndex.allValues sortedArrayUsingComparator:^NSComparisonResult(CacheItem *obj1, CacheItem *obj2) {
        return [obj1.lastAccessTime compare:obj2.lastAccessTime];
    }];
    
    NSInteger removed = 0;
    for (CacheItem *item in sortedItems) {
        if (removed >= count) break;
        
        [self removeCacheItem:item];
        removed++;
    }
    
    [self updateStatistics];
    NSLog(@"[CacheManager] LRU清理完成，删除了%ld个文件", (long)removed);
}

- (void)performLRUCleanupToSize:(NSUInteger)targetSize {
    // 按最后访问时间排序
    NSArray *sortedItems = [self.cacheIndex.allValues sortedArrayUsingComparator:^NSComparisonResult(CacheItem *obj1, CacheItem *obj2) {
        return [obj1.lastAccessTime compare:obj2.lastAccessTime];
    }];
    
    NSUInteger currentSize = self.stats.totalSize;
    NSInteger removed = 0;
    
    for (CacheItem *item in sortedItems) {
        if (currentSize <= targetSize) break;
        
        currentSize -= item.fileSize;
        [self removeCacheItem:item];
        removed++;
    }
    
    [self updateStatistics];
    NSLog(@"[CacheManager] LRU大小清理完成，删除了%ld个文件，当前大小%.2fMB", 
          (long)removed, currentSize / (1024.0 * 1024.0));
}

@end
