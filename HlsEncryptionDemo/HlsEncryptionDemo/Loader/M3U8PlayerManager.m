//
//  M3U8PlayerManager.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8PlayerManager.h"
#import "M3U8Parser.h"
#import "QualitySelector.h"
#import "CacheManager.h"
#import "M3U8KeyManager.h"
#import "AFNetworking.h"

@interface M3U8PlayerManager () <M3U8ParserDelegate, QualitySelectorDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *currentPlayerItem;
@property (nonatomic, strong) MasterPlaylist *currentMasterPlaylist;
@property (nonatomic, strong) StreamInfo *currentStream;
@property (nonatomic, strong) MediaPlaylist *currentMediaPlaylist;

@property (nonatomic, strong) M3U8Parser *parser;
@property (nonatomic, strong) QualitySelector *qualitySelector;
@property (nonatomic, strong) CacheManager *cacheManager;
@property (nonatomic, strong) M3U8KeyManager *keyManager;
@property (nonatomic, strong) M3U8AuthConfig *authConfig;

@property (nonatomic, strong) NSString *currentVideoURL;
@property (nonatomic, strong) NSString *preferredQuality;
@property (nonatomic, strong) AFHTTPSessionManager *sessionManager; // 保持session管理器的引用

@end

@implementation M3U8PlayerManager

+ (instancetype)sharedManager {
    static M3U8PlayerManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[M3U8PlayerManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self setupComponents];
    }
    return self;
}

- (void)setupComponents {
    // 初始化核心组件
    _parser = [[M3U8Parser alloc] init];
    _parser.delegate = self;
    
    _qualitySelector = [[QualitySelector alloc] init];
    _qualitySelector.delegate = self;
    
    _cacheManager = [CacheManager sharedManager];
    _keyManager = [M3U8KeyManager sharedManager];
    
    // 初始化播放器
    _player = [[AVPlayer alloc] init];
    
    NSLog(@"[M3U8PlayerManager] 组件初始化完成");
}

#pragma mark - Public Methods

- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self.authConfig = authConfig;
    [self.keyManager configureWithAuthConfig:authConfig];
    NSLog(@"[M3U8PlayerManager] 授权配置完成: %@", [authConfig authParamsString]);
}

- (void)playVideoWithURL:(NSString *)url preferredQuality:(NSString *)preferredQuality {
    NSLog(@"[M3U8PlayerManager] 开始播放视频: %@, 偏好清晰度: %@", url, preferredQuality);
    
    self.currentVideoURL = url;
    self.preferredQuality = preferredQuality;
    
    // 清理之前的播放状态
    [self cleanupCurrentPlayback];
    
    // 下载并解析主M3U8
    [self downloadAndParseMasterPlaylist:url];
}

- (void)switchToQuality:(NSString *)quality {
    if (!self.currentMasterPlaylist) {
        NSLog(@"[M3U8PlayerManager] 没有可用的主播放列表，无法切换清晰度");
        return;
    }
    
    NSLog(@"[M3U8PlayerManager] 切换清晰度到: %@", quality);
    self.preferredQuality = quality;
    
    // 使用清晰度选择器选择新的流
    StreamInfo *newStream = [self.qualitySelector selectStreamForQuality:quality 
                                                        fromMasterPlaylist:self.currentMasterPlaylist];
    
    if (newStream && ![newStream.url isEqualToString:self.currentStream.url]) {
        // 加载新的流
        [self loadStreamPlaylist:newStream];
    }
}

- (void)pause {
    [self.player pause];
    NSLog(@"[M3U8PlayerManager] 播放暂停");
}

- (void)resume {
    [self.player play];
    NSLog(@"[M3U8PlayerManager] 播放继续");
}

- (void)stop {
    [self.player pause];
    [self cleanupCurrentPlayback];
    NSLog(@"[M3U8PlayerManager] 播放停止");
}

- (NSArray<NSString *> *)availableQualities {
    if (!self.currentMasterPlaylist) {
        return @[];
    }
    return [self.currentMasterPlaylist availableQualityLevels];
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

- (void)clearCache {
    [self.cacheManager clearAllCache];
    NSLog(@"[M3U8PlayerManager] 缓存已清空");
}

#pragma mark - Private Methods


- (void)cleanupCurrentPlayback {
    // 取消并释放session
    if (self.sessionManager) {
        [self.sessionManager.session invalidateAndCancel];
        self.sessionManager = nil;
    }
    
    if (self.currentPlayerItem) {
        [self.currentPlayerItem removeObserver:self forKeyPath:@"status"];
        self.currentPlayerItem = nil;
    }
    
    self.currentMasterPlaylist = nil;
    self.currentStream = nil;
    self.currentMediaPlaylist = nil;
}

- (void)testSimpleNetworkRequest:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] 开始简单网络连接测试...");
    
    NSURLRequest *testRequest = [NSURLRequest requestWithURL:[NSURL URLWithString:url]];
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = 10.0;
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];
    
    NSURLSessionDataTask *testTask = [session dataTaskWithRequest:testRequest completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            NSLog(@"[M3U8PlayerManager] 简单网络测试失败: %@", error.localizedDescription);
        } else {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[M3U8PlayerManager] 简单网络测试成功 - 状态码: %ld, 数据长度: %lu", 
                  (long)httpResponse.statusCode, (unsigned long)data.length);
        }
        [session finishTasksAndInvalidate];
    }];
    
    [testTask resume];
}

- (void)downloadAndParseMasterPlaylist:(NSString *)url {
    // 先进行简单的网络连接测试
    [self testSimpleNetworkRequest:url];
    
    // 生成缓存键
    NSString *token = self.authConfig ? [self.authConfig authParamsString] : @"";
    
    // 先检查缓存
    NSData *cachedData = [self.cacheManager cachedDataForURL:url token:token];
    if (cachedData) {
        NSLog(@"[M3U8PlayerManager] 使用缓存的主播放列表");
        if ([self.delegate respondsToSelector:@selector(playerManager:cacheHitForURL:)]) {
            [self.delegate playerManager:self cacheHitForURL:url];
        }
        
        NSString *content = [[NSString alloc] initWithData:cachedData encoding:NSUTF8StringEncoding];
        [self.parser parseMasterPlaylistAsync:content baseURL:url completion:nil];
        return;
    }
    
    // 缓存未命中，从网络下载
    NSLog(@"[M3U8PlayerManager] 从网络下载主播放列表: %@", url);
    if ([self.delegate respondsToSelector:@selector(playerManager:cacheMissForURL:)]) {
        [self.delegate playerManager:self cacheMissForURL:url];
    }
    
    // 创建临时文件路径
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tempFilePath = [tempDir stringByAppendingPathComponent:@"master.m3u8"];
    
    // 配置Session（使用实例变量保持引用）
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 60.0;
    self.sessionManager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
    AFHTTPSessionManager *manager = self.sessionManager;
    
    // 创建请求
    NSURL *requestURL = [NSURL URLWithString:url];
    if (!requestURL) {
        NSLog(@"[M3U8PlayerManager] 无效的URL: %@", url);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:requestURL];
    [request setValue:@"M3U8Player/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"*/*" forHTTPHeaderField:@"Accept"];
    [request setValue:@"gzip, deflate" forHTTPHeaderField:@"Accept-Encoding"];
    [request setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    
    NSLog(@"[M3U8PlayerManager] 创建请求 - URL: %@", requestURL);
    NSLog(@"[M3U8PlayerManager] 请求头: %@", request.allHTTPHeaderFields);
    NSLog(@"[M3U8PlayerManager] 超时设置 - Request: %.1fs, Resource: %.1fs", 
          configuration.timeoutIntervalForRequest, configuration.timeoutIntervalForResource);
    
    __weak __typeof(self)weakSelf = self;
    NSURLSessionDownloadTask *task = [manager downloadTaskWithRequest:request progress:^(NSProgress * _Nonnull downloadProgress) {
        CGFloat progress = downloadProgress.fractionCompleted;
        NSLog(@"[M3U8PlayerManager] 下载进度: %.2f%% (%lld/%lld bytes)", 
              progress * 100, downloadProgress.completedUnitCount, downloadProgress.totalUnitCount);
    } destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        NSLog(@"[M3U8PlayerManager] 下载目标路径: %@", tempFilePath);
        if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[M3U8PlayerManager] HTTP响应 - 状态码: %ld, 头部: %@", 
                  (long)httpResponse.statusCode, httpResponse.allHeaderFields);
        }
        // 返回临时存储目录
        return [NSURL fileURLWithPath:tempFilePath];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"[M3U8PlayerManager] strongSelf为nil，可能已经被释放");
            return;
        }
        
        NSLog(@"[M3U8PlayerManager] 下载任务完成回调");
        NSLog(@"[M3U8PlayerManager] 下载文件路径: %@", filePath);
        
        if (error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[M3U8PlayerManager] 下载失败详情:");
            NSLog(@"  - 错误码: %ld", (long)error.code);
            NSLog(@"  - 错误域: %@", error.domain);
            NSLog(@"  - 错误描述: %@", error.localizedDescription);
            NSLog(@"  - 用户信息: %@", error.userInfo);
            NSLog(@"  - HTTP状态码: %ld", httpResponse ? (long)httpResponse.statusCode : 0);
            
            // 检查常见错误类型
            if (error.code == NSURLErrorCancelled) {
                NSLog(@"[M3U8PlayerManager] 请求被取消 - 可能原因：应用退后台、网络切换、或手动取消");
            } else if (error.code == NSURLErrorTimedOut) {
                NSLog(@"[M3U8PlayerManager] 请求超时");
            } else if (error.code == NSURLErrorNotConnectedToInternet) {
                NSLog(@"[M3U8PlayerManager] 网络未连接");
            } else if (error.code == NSURLErrorNetworkConnectionLost) {
                NSLog(@"[M3U8PlayerManager] 网络连接丢失");
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
                }
            });
            
            // 清理临时文件
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }
        
        // 读取下载的文件
        NSData *data = [NSData dataWithContentsOfFile:tempFilePath];
        if (!data) {
            NSError *readError = [NSError errorWithDomain:@"M3U8PlayerError" 
                                                     code:1001 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无法读取下载的M3U8文件"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:readError];
                }
            });
            
            // 清理临时文件
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }
        
        NSLog(@"[M3U8PlayerManager] 主播放列表下载成功，大小: %lu bytes", (unsigned long)data.length);
        
        // 缓存数据
        [strongSelf.cacheManager cacheData:data forURL:url token:token];
        
        // 解析内容
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (content) {
            [strongSelf.parser parseMasterPlaylistAsync:content baseURL:url completion:nil];
        } else {
            NSError *parseError = [NSError errorWithDomain:@"M3U8PlayerError" 
                                                      code:1002 
                                                  userInfo:@{NSLocalizedDescriptionKey: @"M3U8文件编码解析失败"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:parseError];
                }
            });
        }
        
        // 清理临时文件
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    }];
    
    // 开始下载
    NSLog(@"[M3U8PlayerManager] 主播放列表任务创建完成，开始下载...");
    NSLog(@"[M3U8PlayerManager] 任务状态: %ld", (long)task.state);
    NSLog(@"[M3U8PlayerManager] Session配置: %@", manager.session.configuration);
    
    [task resume];
    
    NSLog(@"[M3U8PlayerManager] 主播放列表任务已启动，当前状态: %ld", (long)task.state);
}

- (void)loadStreamPlaylist:(StreamInfo *)stream {
    NSString *streamURL = stream.url;
    NSString *token = self.authConfig ? [self.authConfig authParamsString] : @"";
    
    // 先检查缓存
    NSData *cachedData = [self.cacheManager cachedDataForURL:streamURL token:token];
    if (cachedData) {
        NSLog(@"[M3U8PlayerManager] 使用缓存的子流播放列表");
        NSString *content = [[NSString alloc] initWithData:cachedData encoding:NSUTF8StringEncoding];
        [self.parser parseMediaPlaylistAsync:content baseURL:streamURL completion:^(MediaPlaylist * _Nullable playlist, NSError * _Nullable error) {
            if (playlist) {
                [self setupPlayerWithMediaPlaylist:playlist stream:stream];
            }
        }];
        return;
    }
    
    // 从网络下载
    NSLog(@"[M3U8PlayerManager] 从网络下载子流播放列表: %@", streamURL);
    
    // 创建临时文件路径
    NSString *tempDir = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    [[NSFileManager defaultManager] createDirectoryAtPath:tempDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tempFilePath = [tempDir stringByAppendingPathComponent:@"stream.m3u8"];
    
    // 配置Session
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration defaultSessionConfiguration];
    configuration.timeoutIntervalForRequest = 30.0;
    configuration.timeoutIntervalForResource = 60.0;
    AFHTTPSessionManager *manager = [[AFHTTPSessionManager alloc] initWithSessionConfiguration:configuration];
    
    // 创建请求
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:streamURL]];
    [request setValue:@"M3U8Player/2.0.0" forHTTPHeaderField:@"User-Agent"];
    [request setCachePolicy:NSURLRequestReloadIgnoringCacheData];
    
    __weak __typeof(self)weakSelf = self;
    NSURLSessionDownloadTask *task = [manager downloadTaskWithRequest:request progress:nil destination:^NSURL * _Nonnull(NSURL * _Nonnull targetPath, NSURLResponse * _Nonnull response) {
        // 返回临时存储目录
        return [NSURL fileURLWithPath:tempFilePath];
    } completionHandler:^(NSURLResponse * _Nonnull response, NSURL * _Nullable filePath, NSError * _Nullable error) {
        __strong __typeof(weakSelf)strongSelf = weakSelf;
        if (!strongSelf) return;
        
        [manager.session finishTasksAndInvalidate];
        
        if (error) {
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSLog(@"[M3U8PlayerManager] 子流播放列表下载失败: %@, HTTP状态码: %ld", 
                  error.localizedDescription, httpResponse ? (long)httpResponse.statusCode : 0);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
                }
            });
            
            // 清理临时文件
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }
        
        // 读取下载的文件
        NSData *data = [NSData dataWithContentsOfFile:tempFilePath];
        if (!data) {
            NSError *readError = [NSError errorWithDomain:@"M3U8PlayerError" 
                                                     code:1003 
                                                 userInfo:@{NSLocalizedDescriptionKey: @"无法读取下载的子流M3U8文件"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:readError];
                }
            });
            
            // 清理临时文件
            [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
            return;
        }
        
        NSLog(@"[M3U8PlayerManager] 子流播放列表下载成功，大小: %lu bytes", (unsigned long)data.length);
        
        // 缓存数据
        [strongSelf.cacheManager cacheData:data forURL:streamURL token:token];
        
        // 解析内容
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (content) {
            [strongSelf.parser parseMediaPlaylistAsync:content baseURL:streamURL completion:^(MediaPlaylist * _Nullable playlist, NSError * _Nullable error) {
                if (playlist) {
                    [strongSelf setupPlayerWithMediaPlaylist:playlist stream:stream];
                } else if (error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                            [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
                        }
                    });
                }
            }];
        } else {
            NSError *parseError = [NSError errorWithDomain:@"M3U8PlayerError" 
                                                      code:1004 
                                                  userInfo:@{NSLocalizedDescriptionKey: @"子流M3U8文件编码解析失败"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:parseError];
                }
            });
        }
        
        // 清理临时文件
        [[NSFileManager defaultManager] removeItemAtPath:tempDir error:nil];
    }];
    
    // 开始下载
    [task resume];
}

- (void)setupPlayerWithMediaPlaylist:(MediaPlaylist *)mediaPlaylist stream:(StreamInfo *)stream {
    self.currentMediaPlaylist = mediaPlaylist;
    self.currentStream = stream;
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(playerManager:didLoadMediaPlaylist:)]) {
        [self.delegate playerManager:self didLoadMediaPlaylist:mediaPlaylist];
    }
    
    // 设置播放器
    NSString *playURL = stream.url;
    
    // 如果有加密信息，需要使用自定义scheme让KeyManager拦截
    if (mediaPlaylist.encryptionInfo) {
        playURL = [playURL stringByReplacingOccurrencesOfString:@"https://" withString:@"m3u8-custom://"];
    }
    
    NSURL *url = [NSURL URLWithString:playURL];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    // 配置密钥管理器
    if (mediaPlaylist.encryptionInfo) {
        [self.keyManager setupResourceLoaderForAsset:asset];
    }
    
    // 创建播放项
    self.currentPlayerItem = [AVPlayerItem playerItemWithAsset:asset];
    
    // 观察播放状态
    [self.currentPlayerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    // 设置到播放器
    [self.player replaceCurrentItemWithPlayerItem:self.currentPlayerItem];
    
    NSLog(@"[M3U8PlayerManager] 播放器设置完成，开始播放");
    [self.player play];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"] && object == self.currentPlayerItem) {
        AVPlayerItemStatus status = [change[NSKeyValueChangeNewKey] integerValue];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(playerManager:playerDidChangeState:)]) {
                [self.delegate playerManager:self playerDidChangeState:status];
            }
            
            switch (status) {
                case AVPlayerItemStatusReadyToPlay:
                    NSLog(@"[M3U8PlayerManager] 播放器准备就绪");
                    break;
                case AVPlayerItemStatusFailed:
                    NSLog(@"[M3U8PlayerManager] 播放器失败: %@", self.currentPlayerItem.error);
                    if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                        [self.delegate playerManager:self didFailWithError:self.currentPlayerItem.error];
                    }
                    break;
                case AVPlayerItemStatusUnknown:
                    NSLog(@"[M3U8PlayerManager] 播放器状态未知");
                    break;
            }
        });
    }
}

#pragma mark - M3U8ParserDelegate

- (void)parser:(id)parser didParseMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    NSLog(@"[M3U8PlayerManager] 主播放列表解析完成，包含%lu个流", (unsigned long)masterPlaylist.streams.count);
    
    // 打印主播放列表详细信息
    [masterPlaylist printDetailedInfo];
    
    self.currentMasterPlaylist = masterPlaylist;
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(playerManager:didLoadMasterPlaylist:)]) {
        [self.delegate playerManager:self didLoadMasterPlaylist:masterPlaylist];
    }
    
    // 选择合适的流
    NSLog(@"[M3U8PlayerManager] 开始选择清晰度，偏好: %@", self.preferredQuality);
    StreamInfo *selectedStream = [self.qualitySelector selectStreamForQuality:self.preferredQuality 
                                                            fromMasterPlaylist:masterPlaylist];
    
    if (selectedStream) {
        NSLog(@"[M3U8PlayerManager] 清晰度选择完成:");
        NSLog(@"  - 选择的流: %@ (%dx%d)", [selectedStream qualityLevel], (int)selectedStream.width, (int)selectedStream.height);
        NSLog(@"  - 带宽: %.1f kbps", selectedStream.bandwidth / 1000.0);
        NSLog(@"  - URL: %@", selectedStream.url);
        [self loadStreamPlaylist:selectedStream];
    } else {
        NSLog(@"[M3U8PlayerManager] ⚠️ 未能选择到合适的流!");
    }
}

- (void)parser:(id)parser didParseMediaPlaylist:(MediaPlaylist *)mediaPlaylist {
    NSLog(@"[M3U8PlayerManager] 媒体播放列表解析完成，包含%lu个片段", (unsigned long)mediaPlaylist.segments.count);
    
    // 打印媒体播放列表详细信息
    [mediaPlaylist printDetailedInfo];
}

- (void)parser:(id)parser didFailWithError:(NSError *)error {
    NSLog(@"[M3U8PlayerManager] 解析失败: %@", error.localizedDescription);
    if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
        [self.delegate playerManager:self didFailWithError:error];
    }
}

#pragma mark - QualitySelectorDelegate

- (void)qualitySelector:(id)selector didSelectStream:(StreamInfo *)stream forQuality:(NSString *)quality {
    NSLog(@"[M3U8PlayerManager] 清晰度选择完成: %@ -> %@", quality, stream);
    if ([self.delegate respondsToSelector:@selector(playerManager:didSelectStream:forQuality:)]) {
        [self.delegate playerManager:self didSelectStream:stream forQuality:quality];
    }
}

- (void)qualitySelector:(id)selector didFailToSelectQuality:(NSString *)quality withError:(NSError *)error {
    NSLog(@"[M3U8PlayerManager] 清晰度选择失败: %@", error.localizedDescription);
    if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
        [self.delegate playerManager:self didFailWithError:error];
    }
}

- (void)dealloc {
    [self cleanupCurrentPlayback];
}

@end
