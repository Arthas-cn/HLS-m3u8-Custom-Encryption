//
//  M3U8Loader.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8Loader.h"
#import "CacheManager.h"
#import "AFNetworking.h"

@interface M3U8Loader ()

@property (nonatomic, strong) M3U8AuthConfig *authConfig;
@property (nonatomic, strong) CacheManager *cacheManager;
@property (nonatomic, strong) NSMutableDictionary<NSString *, AFHTTPSessionManager *> *sessionManagers;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSURLSessionDownloadTask *> *downloadTasks;
@property (nonatomic, strong) NSMutableDictionary<NSString *, void(^)(NSString * _Nullable, NSError * _Nullable)> *completionBlocks;
@property (nonatomic, strong) dispatch_queue_t loaderQueue;

@end

@implementation M3U8Loader

#pragma mark - Lifecycle

+ (instancetype)sharedLoader {
    static M3U8Loader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[M3U8Loader alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cacheManager = [CacheManager sharedManager];
        _sessionManagers = [NSMutableDictionary dictionary];
        _downloadTasks = [NSMutableDictionary dictionary];
        _completionBlocks = [NSMutableDictionary dictionary];
        _loaderQueue = dispatch_queue_create("com.m3u8loader.queue", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (void)dealloc {
    [self cancelAllLoads];
}

#pragma mark - Public Methods

- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self.authConfig = authConfig;
    NSLog(@"[M3U8Loader] 授权配置完成: %@", authConfig ? [authConfig authParamsString] : @"无");
}

- (void)loadM3U8WithURL:(NSString *)url {
    [self loadM3U8WithURL:url completion:nil];
}

- (void)loadM3U8WithURL:(NSString *)url 
             completion:(void(^)(NSString * _Nullable content, NSError * _Nullable error))completion {
    
    if (!url || url.length == 0) {
        NSError *error = [NSError errorWithDomain:@"M3U8Loader" 
                                           code:1001 
                                       userInfo:@{NSLocalizedDescriptionKey: @"URL不能为空"}];
        [self notifyFailure:error forURL:url completion:completion];
        return;
    }
    
    NSLog(@"[M3U8Loader] 开始加载M3U8文件: %@", url);
    
    // 生成缓存键
    NSString *token = self.authConfig ? [self.authConfig authParamsString] : @"";
    
    // 先检查缓存
    NSData *cachedData = [self.cacheManager cachedDataForURL:url token:token];
    if (cachedData) {
        NSLog(@"[M3U8Loader] 缓存命中: %@", url);
        
        // 通知缓存命中
        if ([self.delegate respondsToSelector:@selector(loader:cacheHitForURL:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate loader:self cacheHitForURL:url];
            });
        }
        
        NSString *content = [[NSString alloc] initWithData:cachedData encoding:NSUTF8StringEncoding];
        [self notifySuccess:content forURL:url completion:completion];
        return;
    }
    
    // 缓存未命中，从网络下载
    NSLog(@"[M3U8Loader] 缓存未命中，从网络下载: %@", url);
    
    // 通知缓存未命中
    if ([self.delegate respondsToSelector:@selector(loader:cacheMissForURL:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loader:self cacheMissForURL:url];
        });
    }
    
    // 检查是否已经有相同URL的请求在进行
    if (self.downloadTasks[url] || self.sessionManagers[url]) {
        NSLog(@"[M3U8Loader] URL已在下载中，忽略重复请求: %@", url);
        if (completion) {
            // 如果已有请求在进行，将回调添加到待处理列表
            // 这里简化处理：直接返回错误，让上层重试
            NSError *error = [NSError errorWithDomain:@"M3U8Loader" 
                                               code:1004 
                                           userInfo:@{NSLocalizedDescriptionKey: @"相同URL的请求正在进行中"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(nil, error);
            });
        }
        return;
    }
    
    // 保存完成回调
    if (completion) {
        self.completionBlocks[url] = completion;
    }
    
    // 开始网络下载
    [self performNetworkDownload:url token:token];
}

- (void)cancelLoadForURL:(NSString *)url {
    if (!url) return;
    
    NSLog(@"[M3U8Loader] 取消加载: %@", url);
    
    // 取消下载任务
    NSURLSessionDownloadTask *task = self.downloadTasks[url];
    if (task) {
        [task cancel];
        [self.downloadTasks removeObjectForKey:url];
    }
    
    // 清理Session管理器
    AFHTTPSessionManager *sessionManager = self.sessionManagers[url];
    if (sessionManager) {
        [sessionManager.session invalidateAndCancel];
        [self.sessionManagers removeObjectForKey:url];
    }
    
    // 通知取消并清理完成回调
    void(^completion)(NSString *, NSError *) = self.completionBlocks[url];
    if (completion) {
        NSError *cancelError = [NSError errorWithDomain:NSURLErrorDomain 
                                                 code:NSURLErrorCancelled 
                                             userInfo:@{NSLocalizedDescriptionKey: @"请求已被取消"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, cancelError);
        });
    }
    [self.completionBlocks removeObjectForKey:url];
}

- (void)cancelAllLoads {
    NSLog(@"[M3U8Loader] 取消所有加载请求");
    
    // 取消所有下载任务
    for (NSURLSessionDownloadTask *task in self.downloadTasks.allValues) {
        [task cancel];
    }
    [self.downloadTasks removeAllObjects];
    
    // 清理所有Session管理器
    for (AFHTTPSessionManager *sessionManager in self.sessionManagers.allValues) {
        [sessionManager.session invalidateAndCancel];
    }
    [self.sessionManagers removeAllObjects];
    
    // 清理所有完成回调
    [self.completionBlocks removeAllObjects];
}

- (void)clearCache {
    [self.cacheManager clearAllCache];
    NSLog(@"[M3U8Loader] 缓存已清空");
}

- (NSDictionary *)cacheStatistics {
    CacheStatistics *stats = [self.cacheManager statistics];
    return @{
        @"fileCount": @(stats.fileCount),
        @"totalSize": @(stats.totalSize),
        @"hitCount": @(stats.hitCount),
        @"missCount": @(stats.missCount),
        @"hitRate": @(stats.hitRate)
    };
}

+ (NSString *)version {
    return @"2.0.0";
}

#pragma mark - Private Methods

- (void)performNetworkDownload:(NSString *)url token:(NSString *)token {
    // 创建临时文件路径
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tempFilePath = [tempDir stringByAppendingPathComponent:@"m3u8_file.m3u8"];
    
    // 配置Session
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 60.0;
    
    AFHTTPSessionManager *sessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
    self.sessionManagers[url] = sessionManager;
    
    // 创建请求
    NSURL *requestURL = [NSURL URLWithString:url];
    if (!requestURL) {
        NSError *error = [NSError errorWithDomain:@"M3U8Loader" 
                                           code:1002 
                                       userInfo:@{NSLocalizedDescriptionKey: @"无效的URL"}];
        [self notifyFailure:error forURL:url completion:self.completionBlocks[url]];
        [self cleanupForURL:url tempDir:tempDir];
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setValue:@"M3U8Player/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
    [request setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    
    NSLog(@"[M3U8Loader] 创建下载请求 - URL: %@", requestURL);
    
    __weak typeof(self) weakSelf = self;
    NSURLSessionDownloadTask *task = [sessionManager downloadTaskWithRequest:request 
                                                                     progress:^(NSProgress * _Nonnull downloadProgress) {
        // 通知下载进度
        float progress = downloadProgress.fractionCompleted;
        NSLog(@"[M3U8Loader] 下载进度: %.2f%% (%lld/%lld bytes)", 
              progress * 100, downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
        
        if ([weakSelf.delegate respondsToSelector:@selector(loader:downloadProgress:forURL:)]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf.delegate loader:weakSelf downloadProgress:progress forURL:url];
            });
        }
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        return [NSURL fileURLWithPath:tempFilePath];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [strongSelf handleDownloadCompletion:response filePath:filePath error:error url:url token:token tempDir:tempDir];
    }];
    
    // 保存下载任务
    self.downloadTasks[url] = task;
    
    // 开始下载
    [task resume];
    NSLog(@"[M3U8Loader] 下载任务已启动: %@", url);
}

- (void)handleDownloadCompletion:(NSURLResponse *)response 
                        filePath:(NSURL *)filePath 
                           error:(NSError *)error 
                             url:(NSString *)url 
                           token:(NSString *)token 
                         tempDir:(NSString *)tempDir {
    
    NSLog(@"[M3U8Loader] 下载完成回调 - URL: %@", url);
    
    // 清理下载任务（但暂时保留session以避免影响其他请求）
    [self.downloadTasks removeObjectForKey:url];
    
    // 立即清理Session管理器（每个URL使用独立的session，不会影响其他请求）
    AFHTTPSessionManager *sessionManager = self.sessionManagers[url];
    if (sessionManager) {
        [sessionManager.session finishTasksAndInvalidate];
        [self.sessionManagers removeObjectForKey:url];
    }
    
    if (error) {
        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        NSLog(@"[M3U8Loader] 下载失败 - URL: %@, 错误: %@, HTTP状态码: %ld", 
              url, error.localizedDescription, httpResponse ? (long)httpResponse.statusCode : 0);
        
        [self notifyFailure:error forURL:url completion:self.completionBlocks[url]];
        [self cleanupForURL:url tempDir:tempDir];
        return;
    }
    
    // 读取下载的文件
    NSData *data = [NSData dataWithContentsOfFile:filePath.path];
    if (!data) {
        NSError *readError = [NSError errorWithDomain:@"M3U8Loader" 
                                               code:1003 
                                           userInfo:@{NSLocalizedDescriptionKey: @"无法读取下载的M3U8文件"}];
        [self notifyFailure:readError forURL:url completion:self.completionBlocks[url]];
        [self cleanupForURL:url tempDir:tempDir];
        return;
    }
    
    NSLog(@"[M3U8Loader] M3U8文件下载成功 - URL: %@, 大小: %lu bytes", url, (unsigned long)data.length);
    
    // 缓存数据
    [self.cacheManager cacheData:data forURL:url token:token];
    
    // 解析内容
    NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (content) {
        [self notifySuccess:content forURL:url completion:self.completionBlocks[url]];
    } else {
        NSError *parseError = [NSError errorWithDomain:@"M3U8Loader" 
                                                code:1004 
                                            userInfo:@{NSLocalizedDescriptionKey: @"M3U8文件编码解析失败"}];
        [self notifyFailure:parseError forURL:url completion:self.completionBlocks[url]];
    }
    
    [self cleanupForURL:url tempDir:tempDir];
}

- (void)notifySuccess:(NSString *)content forURL:(NSString *)url completion:(void(^)(NSString * _Nullable, NSError * _Nullable))completion {
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(loader:didLoadContent:fromURL:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loader:self didLoadContent:content fromURL:url];
        });
    }
    
    // 执行完成回调
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(content, nil);
        });
    }
}

- (void)notifyFailure:(NSError *)error forURL:(NSString *)url completion:(void(^)(NSString * _Nullable, NSError * _Nullable))completion {
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(loader:didFailWithError:forURL:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate loader:self didFailWithError:error forURL:url];
        });
    }
    
    // 执行完成回调
    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error);
        });
    }
}

- (void)cleanupForURL:(NSString *)url tempDir:(NSString *)tempDir {
    // 清理完成回调
    [self.completionBlocks removeObjectForKey:url];
    
    // 清理临时文件
    [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
}

@end
