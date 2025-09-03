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
    if (self.currentPlayerItem) {
        [self.currentPlayerItem removeObserver:self forKeyPath:@"status"];
        self.currentPlayerItem = nil;
    }
    
    self.currentMasterPlaylist = nil;
    self.currentStream = nil;
    self.currentMediaPlaylist = nil;
}

- (void)downloadAndParseMasterPlaylist:(NSString *)url {
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
    NSLog(@"[M3U8PlayerManager] 从网络下载主播放列表");
    if ([self.delegate respondsToSelector:@selector(playerManager:cacheMissForURL:)]) {
        [self.delegate playerManager:self cacheMissForURL:url];
    }
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [manager GET:url parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSData *data = responseObject;
        
        // 缓存数据
        [self.cacheManager cacheData:data forURL:url token:token];
        
        // 解析内容
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.parser parseMasterPlaylistAsync:content baseURL:url completion:nil];
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"[M3U8PlayerManager] 主播放列表下载失败: %@", error.localizedDescription);
        if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
            [self.delegate playerManager:self didFailWithError:error];
        }
    }];
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
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [manager GET:streamURL parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        NSData *data = responseObject;
        
        // 缓存数据
        [self.cacheManager cacheData:data forURL:streamURL token:token];
        
        // 解析内容
        NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.parser parseMediaPlaylistAsync:content baseURL:streamURL completion:^(MediaPlaylist * _Nullable playlist, NSError * _Nullable error) {
            if (playlist) {
                [self setupPlayerWithMediaPlaylist:playlist stream:stream];
            } else if (error) {
                if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [self.delegate playerManager:self didFailWithError:error];
                }
            }
        }];
        
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"[M3U8PlayerManager] 子流播放列表下载失败: %@", error.localizedDescription);
        if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
            [self.delegate playerManager:self didFailWithError:error];
        }
    }];
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
    
    self.currentMasterPlaylist = masterPlaylist;
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(playerManager:didLoadMasterPlaylist:)]) {
        [self.delegate playerManager:self didLoadMasterPlaylist:masterPlaylist];
    }
    
    // 选择合适的流
    StreamInfo *selectedStream = [self.qualitySelector selectStreamForQuality:self.preferredQuality 
                                                            fromMasterPlaylist:masterPlaylist];
    
    if (selectedStream) {
        [self loadStreamPlaylist:selectedStream];
    }
}

- (void)parser:(id)parser didParseMediaPlaylist:(MediaPlaylist *)mediaPlaylist {
    NSLog(@"[M3U8PlayerManager] 媒体播放列表解析完成，包含%lu个片段", (unsigned long)mediaPlaylist.segments.count);
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
