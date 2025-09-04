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
#import "M3U8KeyManager.h"
#import "M3U8Loader.h"
#import "AFNetworking.h"

@interface M3U8PlayerManager () <M3U8ParserDelegate, QualitySelectorDelegate, M3U8LoaderDelegate>

@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerItem *currentPlayerItem;
@property (nonatomic, strong) MasterPlaylist *currentMasterPlaylist;
@property (nonatomic, strong) StreamInfo *currentStream;
@property (nonatomic, strong) MediaPlaylist *currentMediaPlaylist;

@property (nonatomic, strong) M3U8Parser *parser;
@property (nonatomic, strong) QualitySelector *qualitySelector;
@property (nonatomic, strong) M3U8KeyManager *keyManager;
@property (nonatomic, strong) M3U8Loader *m3u8Loader;
@property (nonatomic, strong) M3U8AuthConfig *authConfig;

@property (nonatomic, strong) NSString *currentVideoURL;
@property (nonatomic, strong) NSString *preferredQuality;

// 无缝切换相关属性
@property (nonatomic, assign) CMTime savedPlayTime;  // 切换清晰度时保存的播放时间
@property (nonatomic, assign) BOOL isQualitySwitching;  // 是否正在切换清晰度
@property (nonatomic, strong) AVPlayerItem *switchPlayerItem;  // 用于切换的新PlayerItem
@property (nonatomic, strong) StreamInfo *switchStream;  // 用于切换的新流信息
@property (nonatomic, strong) MediaPlaylist *switchMediaPlaylist;  // 用于切换的新媒体播放列表
@property(nonatomic, strong) AVPlayer *switchPlayer;

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
        // 初始化无缝切换相关属性
        _savedPlayTime = kCMTimeInvalid;
        _isQualitySwitching = NO;
        _switchPlayerItem = nil;
        _switchStream = nil;
        _switchMediaPlaylist = nil;
        
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
    
    _keyManager = [M3U8KeyManager new];
    _m3u8Loader = [M3U8Loader new];
    _m3u8Loader.delegate = self;
    
    // 初始化播放器
    _player = [[AVPlayer alloc] init];
    
    NSLog(@"[M3U8PlayerManager] 组件初始化完成");
}

#pragma mark - Public Methods

- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self.authConfig = authConfig;
    [self.keyManager configureWithAuthConfig:authConfig];
    [self.m3u8Loader configureWithAuthConfig:authConfig];
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
    
    if (self.isQualitySwitching) {
        NSLog(@"[M3U8PlayerManager] 正在切换清晰度中，忽略本次请求");
        return;
    }
    
    NSLog(@"[M3U8PlayerManager] 开始无缝切换清晰度到: %@", quality);
    
    // 记录当前播放时间
    self.savedPlayTime = [self currentPlayTime];
    if (CMTIME_IS_VALID(self.savedPlayTime)) {
        NSLog(@"[M3U8PlayerManager] 保存当前播放时间: %.2f秒", CMTimeGetSeconds(self.savedPlayTime));
    } else {
        NSLog(@"[M3U8PlayerManager] 无法获取有效的播放时间，使用0秒");
        self.savedPlayTime = kCMTimeZero;
    }
    
    // 设置切换状态
    self.isQualitySwitching = YES;
    self.preferredQuality = quality;
    
    // 通知代理开始切换
    if ([self.delegate respondsToSelector:@selector(playerManager:willSwitchToQuality:)]) {
        [self.delegate playerManager:self willSwitchToQuality:quality];
    }
    
    // 使用清晰度选择器选择新的流
    StreamInfo *newStream = [self.qualitySelector selectStreamForQuality:quality 
                                                        fromMasterPlaylist:self.currentMasterPlaylist];
    
    if (newStream && ![newStream.url isEqualToString:self.currentStream.url]) {
        // 加载新的流并创建switchPlayerItem
        [self loadStreamPlaylistForSwitch:newStream];
    } else {
        // 如果是相同的流，直接完成切换
        self.isQualitySwitching = NO;
        NSLog(@"[M3U8PlayerManager] 已经是目标清晰度，切换完成");
        if ([self.delegate respondsToSelector:@selector(playerManager:didSwitchToQuality:)]) {
            [self.delegate playerManager:self didSwitchToQuality:quality];
        }
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
    return [self.m3u8Loader cacheStatistics];
}

- (void)clearCache {
    [self.m3u8Loader clearCache];
    NSLog(@"[M3U8PlayerManager] 缓存已清空");
}

- (CMTime)currentPlayTime {
    if (self.currentPlayerItem) {
        return self.currentPlayerItem.currentTime;
    }
    return kCMTimeInvalid;
}

- (void)seekToTime:(CMTime)time completionHandler:(void (^)(BOOL finished))completionHandler {
    if (self.currentPlayerItem && CMTIME_IS_VALID(time)) {
        [self.currentPlayerItem seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:completionHandler];
        NSLog(@"[M3U8PlayerManager] 跳转到时间: %.2f秒", CMTimeGetSeconds(time));
    } else if (completionHandler) {
        completionHandler(NO);
    }
}

#pragma mark - Private Methods


- (void)cleanupCurrentPlayback {
    // 取消所有M3U8下载请求
    [self.m3u8Loader cancelAllLoads];
    
    if (self.currentPlayerItem) {
        [self.currentPlayerItem removeObserver:self forKeyPath:@"status"];
        self.currentPlayerItem = nil;
    }
    
    // 清理切换相关的资源
    [self cleanupSwitchPlayerItem];
    self.isQualitySwitching = NO;
    self.savedPlayTime = kCMTimeInvalid;
    
    self.currentMasterPlaylist = nil;
    self.currentStream = nil;
    self.currentMediaPlaylist = nil;
}


- (void)downloadAndParseMasterPlaylist:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] 使用M3U8Loader下载主播放列表: %@", url);
    
    // 使用M3U8Loader下载主播放列表
    __weak __typeof(self) weakSelf = self;
    [self.m3u8Loader loadM3U8WithURL:url completion:^(NSString * _Nullable content, NSError * _Nullable error) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            NSLog(@"[M3U8PlayerManager] strongSelf为nil，可能已经被释放");
            return;
        }
        
        if (error) {
            NSLog(@"[M3U8PlayerManager] 主播放列表下载失败: %@", error.localizedDescription);
            if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
            }
            return;
        }
        
        if (content) {
            NSLog(@"[M3U8PlayerManager] 主播放列表下载成功，开始解析");
            [strongSelf.parser parseMasterPlaylistAsync:content baseURL:url completion:nil];
        } else {
            NSError *parseError = [NSError errorWithDomain:@"M3U8PlayerError" 
                                                      code:1002 
                                                  userInfo:@{NSLocalizedDescriptionKey: @"M3U8文件内容为空"}];
            if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                [strongSelf.delegate playerManager:strongSelf didFailWithError:parseError];
            }
        }
    }];
}

- (void)loadStreamPlaylist:(StreamInfo *)stream {
    NSString *streamURL = stream.url;
    
    NSLog(@"[M3U8PlayerManager] 使用M3U8Loader下载子流播放列表: %@", streamURL);
    
    // 使用M3U8Loader下载子流播放列表
    __weak __typeof(self) weakSelf = self;
    [self.m3u8Loader loadM3U8WithURL:streamURL completion:^(NSString * _Nullable content, NSError * _Nullable error) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"[M3U8PlayerManager] 子流播放列表下载失败: %@", error.localizedDescription);
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
                }
            });
            return;
        }
        
        if (content) {
            NSLog(@"[M3U8PlayerManager] 子流播放列表下载成功，开始解析");
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
                                                  userInfo:@{NSLocalizedDescriptionKey: @"子流M3U8文件内容为空"}];
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:parseError];
                }
            });
        }
    }];
}

- (void)loadStreamPlaylistForSwitch:(StreamInfo *)stream {
    NSString *streamURL = stream.url;
    
    NSLog(@"[M3U8PlayerManager] 为切换加载子流播放列表: %@", streamURL);
    
    // 使用M3U8Loader下载子流播放列表
    __weak __typeof(self) weakSelf = self;
    [self.m3u8Loader loadM3U8WithURL:streamURL completion:^(NSString * _Nullable content, NSError * _Nullable error) {
        __strong __typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        
        if (error) {
            NSLog(@"[M3U8PlayerManager] 切换用子流播放列表下载失败: %@", error.localizedDescription);
            strongSelf.isQualitySwitching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:error];
                }
            });
            return;
        }
        
        if (content) {
            NSLog(@"[M3U8PlayerManager] 切换用子流播放列表下载成功，开始解析");
            [strongSelf.parser parseMediaPlaylistAsync:content baseURL:streamURL completion:^(MediaPlaylist * _Nullable playlist, NSError * _Nullable error) {
                if (playlist) {
                    [strongSelf setupSwitchPlayerItemWithMediaPlaylist:playlist stream:stream];
                } else if (error) {
                    strongSelf.isQualitySwitching = NO;
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
                                                  userInfo:@{NSLocalizedDescriptionKey: @"切换用子流M3U8文件内容为空"}];
            strongSelf.isQualitySwitching = NO;
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([strongSelf.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                    [strongSelf.delegate playerManager:strongSelf didFailWithError:parseError];
                }
            });
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

- (void)setupSwitchPlayerItemWithMediaPlaylist:(MediaPlaylist *)mediaPlaylist stream:(StreamInfo *)stream {
    NSLog(@"[M3U8PlayerManager] 设置切换用的PlayerItem，流URL: %@", stream.url);
    
    // 保存即将切换的流信息
    self.switchStream = stream;
    self.switchMediaPlaylist = mediaPlaylist;
    
    // 设置播放器
    NSString *playURL = stream.url;
    
    // 如果有加密信息，需要使用自定义scheme让KeyManager拦截
    if (mediaPlaylist.encryptionInfo) {
        playURL = [playURL stringByReplacingOccurrencesOfString:@"https://" withString:@"m3u8-custom://"];
        NSLog(@"[M3U8PlayerManager] 检测到加密信息，使用自定义scheme: %@", playURL);
    }
    
    NSURL *url = [NSURL URLWithString:playURL];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    // 配置密钥管理器
    if (mediaPlaylist.encryptionInfo) {
        [self.keyManager setupResourceLoaderForAsset:asset];
        NSLog(@"[M3U8PlayerManager] 为切换PlayerItem配置密钥管理器");
    }
    
    // 创建切换用的播放项
    self.switchPlayerItem = [AVPlayerItem playerItemWithAsset:asset];
    NSLog(@"[M3U8PlayerManager] 创建switchPlayerItem: %p", self.switchPlayerItem);
    
    // 观察切换播放项的状态
    [self addNotiWithAVItem:self.switchPlayerItem];
    NSLog(@"[M3U8PlayerManager] 已添加switchPlayerItem的KVO观察器");
    
    // 检查初始状态
    
    NSLog(@"[M3U8PlayerManager] 切换用PlayerItem创建完成，等待准备就绪");
    
    AVPlayer *player = [AVPlayer playerWithPlayerItem:self.switchPlayerItem];
    _switchPlayer = player;
    [player seekToTime:_savedPlayTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
    }];
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSKeyValueChangeKey,id> *)change context:(void *)context {
    
    if (object == self.currentPlayerItem) {
        [self currentPlayerItemKeyPath:keyPath change:change];
    }
    
    if (object == self.switchPlayerItem) {
        [self switchPlayerItemKeyPath:keyPath change:change];
    }
    
}

/// 当前播放处理
- (void)currentPlayerItemKeyPath:(NSString *)keyPath change:(NSDictionary<NSKeyValueChangeKey,id> *)change {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItemStatus status = [change[NSKeyValueChangeNewKey] integerValue];
        NSLog(@"[M3U8PlayerManager] 检测到当前PlayerItem状态变化: %ld", (long)status);
        dispatch_async(dispatch_get_main_queue(), ^{
            if ([self.delegate respondsToSelector:@selector(playerManager:playerDidChangeState:)]) {
                [self.delegate playerManager:self playerDidChangeState:status];
            }
            
            switch (status) {
                case AVPlayerItemStatusReadyToPlay:
                    NSLog(@"[M3U8PlayerManager] 当前播放器准备就绪");
                    break;
                case AVPlayerItemStatusFailed:
                    NSLog(@"[M3U8PlayerManager] 当前播放器失败: %@", self.currentPlayerItem.error);
                    if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                        [self.delegate playerManager:self didFailWithError:self.currentPlayerItem.error];
                    }
                    break;
                case AVPlayerItemStatusUnknown:
                    NSLog(@"[M3U8PlayerManager] 当前播放器状态未知");
                    break;
            }
        });
    }
}

/// 切换播放处理
- (void)switchPlayerItemKeyPath:(NSString *)keyPath change:(NSDictionary<NSKeyValueChangeKey,id> *)change {
    if ([keyPath isEqualToString:@"status"]) {
        AVPlayerItemStatus status = [change[NSKeyValueChangeNewKey] integerValue];

        dispatch_async(dispatch_get_main_queue(), ^{
            
            switch (status) {
                case AVPlayerItemStatusReadyToPlay:
                    NSLog(@"[切换播放器] 当前播放器准备就绪");
                    break;
                case AVPlayerItemStatusFailed:
                    {
                        NSError *error = self.switchPlayerItem.error;
                        NSLog(@"[切换播放器] 当前播放器失败: %@", error);
                        if ([self.delegate respondsToSelector:@selector(playerManager:didFailWithError:)]) {
                            [self.delegate playerManager:self didFailWithError:error];
                        }
                        [self cleanupSwitchPlayerItem];
                        self.isQualitySwitching = NO;
                    }
                    break;
                case AVPlayerItemStatusUnknown:
                    NSLog(@"[切换播放器] 当前播放器状态未知");
                    break;
            }
        });
    }else if ([keyPath isEqualToString:@"loadedTimeRanges"]) {
        NSArray *timeRanges = (NSArray *)[self.switchPlayerItem loadedTimeRanges];
        //完善 缓冲时间 是否 大过当前播放时间
        CMTime currentTime = [_player currentTime];
        BOOL pass = NO;
        
        // 检查已缓冲的时间范围是否包含或超过当前播放时间
        for (NSValue *timeRangeValue in timeRanges) {
            CMTimeRange timeRange = [timeRangeValue CMTimeRangeValue];
            CMTime rangeStart = timeRange.start;
            CMTime rangeEnd = CMTimeAdd(timeRange.start, timeRange.duration);
            
            // 如果当前时间在缓冲范围内，或者缓冲时间超过当前时间
            if (CMTimeCompare(currentTime, rangeStart) >= 0 && CMTimeCompare(currentTime, rangeEnd) <= 0) {
                pass = YES;
                break;
            }
        }
        
        NSLog(@"[切换播放器] 缓冲检查 - 当前时间: %.2fs, 缓冲范围数: %ld, 检查通过: %@", 
              CMTimeGetSeconds(currentTime), (long)timeRanges.count, pass ? @"是" : @"否");
        if (pass) {
            [self performSeamlessSwitch];
        }
    }
}


- (void)performSeamlessSwitch {
    if (!self.switchPlayerItem || !CMTIME_IS_VALID(self.savedPlayTime)) {
        NSLog(@"[M3U8PlayerManager] 无缝切换条件不满足");
        [self cleanupSwitchPlayerItem];
        self.isQualitySwitching = NO;
        return;
    }
    NSLog(@"[M3U8PlayerManager] 开始执行无缝切换：先跳转到时间点 %.2f秒", CMTimeGetSeconds(self.savedPlayTime));
    
    NSLog(@"[M3U8PlayerManager] 时间跳转完成，开始替换PlayerItem");
    
    // 清理当前PlayerItem的观察者
    if (self.currentPlayerItem) {
        [self.currentPlayerItem removeObserver:self forKeyPath:@"status"];
    }
    [_switchPlayer pause];
    [_switchPlayer replaceCurrentItemWithPlayerItem:nil];
    _switchPlayer = nil;
    
    // 替换当前PlayerItem和流信息
    self.currentPlayerItem = [AVPlayerItem playerItemWithAsset:_switchPlayerItem.asset];
    self.currentStream = self.switchStream;
    self.currentMediaPlaylist = self.switchMediaPlaylist;
    
    // 清空切换用的变量
    [self cleanupSwitchPlayerItem];
    self.switchPlayerItem = nil;
    self.switchStream = nil;
    self.switchMediaPlaylist = nil;
    // 为新的PlayerItem添加观察者
    [self.currentPlayerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    // 替换播放器的PlayerItem
    [self.player replaceCurrentItemWithPlayerItem:self.currentPlayerItem];
    [self.player seekToTime:_savedPlayTime toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
        
    }];
    // 通知代理新的流和媒体播放列表
    if ([self.delegate respondsToSelector:@selector(playerManager:didSelectStream:forQuality:)]) {
        [self.delegate playerManager:self didSelectStream:self.currentStream forQuality:self.preferredQuality];
    }
    if ([self.delegate respondsToSelector:@selector(playerManager:didLoadMediaPlaylist:)]) {
        [self.delegate playerManager:self didLoadMediaPlaylist:self.currentMediaPlaylist];
    }
    
    // 完成切换
    self.isQualitySwitching = NO;
    
    NSLog(@"[M3U8PlayerManager] 无缝清晰度切换完成，新流: %@", self.currentStream.url);
    if ([self.delegate respondsToSelector:@selector(playerManager:didSwitchToQuality:)]) {
        [self.delegate playerManager:self didSwitchToQuality:self.preferredQuality];
    }
}

/// 移除相关通知
- (void)removeNotiWithAVItem:(AVPlayerItem*)playerItem{
    if (playerItem == nil) {
        return;
    }
    [playerItem removeObserver:self forKeyPath:@"status" context:nil];
    [playerItem removeObserver:self forKeyPath:@"loadedTimeRanges" context:nil];
}

/// 监听播放相关通知
- (void)addNotiWithAVItem:(AVPlayerItem*)playerItem{
    if (playerItem == nil) {
        return;
    }
    
    //增加状态监听
    [playerItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    [playerItem addObserver:self forKeyPath:@"loadedTimeRanges" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)cleanupSwitchPlayerItem {
    if (self.switchPlayerItem) {
        [self removeNotiWithAVItem:self.switchPlayerItem];
        self.switchPlayerItem = nil;
    }
    self.switchStream = nil;
    self.switchMediaPlaylist = nil;
    [_switchPlayer replaceCurrentItemWithPlayerItem:nil];
    [_switchPlayer pause];
    self.switchPlayer = nil;
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

#pragma mark - M3U8LoaderDelegate

- (void)loader:(M3U8Loader *)loader didLoadContent:(NSString *)content fromURL:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] M3U8Loader加载成功: %@", url);
    // 这里只是记录日志，实际的内容处理在完成回调中进行
}

- (void)loader:(M3U8Loader *)loader didFailWithError:(NSError *)error forURL:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] M3U8Loader加载失败: %@ - %@", url, error.localizedDescription);
    // 这里只是记录日志，实际的错误处理在完成回调中进行
}

- (void)loader:(M3U8Loader *)loader downloadProgress:(float)progress forURL:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] M3U8下载进度: %.2f%% - %@", progress * 100, url);
    // 可以在这里通知上层代理下载进度
}

- (void)loader:(M3U8Loader *)loader cacheHitForURL:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] M3U8缓存命中: %@", url);
    if ([self.delegate respondsToSelector:@selector(playerManager:cacheHitForURL:)]) {
        [self.delegate playerManager:self cacheHitForURL:url];
    }
}

- (void)loader:(M3U8Loader *)loader cacheMissForURL:(NSString *)url {
    NSLog(@"[M3U8PlayerManager] M3U8缓存未命中: %@", url);
    if ([self.delegate respondsToSelector:@selector(playerManager:cacheMissForURL:)]) {
        [self.delegate playerManager:self cacheMissForURL:url];
    }
}

- (void)dealloc {
    [self cleanupCurrentPlayback];
}

@end
