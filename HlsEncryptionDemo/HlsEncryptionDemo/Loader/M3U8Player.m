//
//  M3U8Player.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8Player.h"
#import "M3U8KeyManager.h"

@interface M3U8Player ()
@property (nonatomic, strong) AVPlayer *player;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) M3U8KeyManager *keyManager;
@property (nonatomic, strong) AVPlayerItem *currentItem;
@property (nonatomic, assign) BOOL isLocalPlayback;
@property (nonatomic, strong) NSString *originalURL;
@end

@implementation M3U8Player

- (instancetype)initWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self = [super init];
    if (self) {
        _authConfig = authConfig ?: [M3U8AuthConfig defaultTestConfig];
        _keyManager = [M3U8KeyManager sharedManager];
        [_keyManager configureWithAuthConfig:_authConfig];
        
        // 设置密钥管理器的代理为当前播放器，用于转发代理事件
        _keyManager.delegate = (id<M3U8PlayerDelegate>)self;
    }
    return self;
}

- (void)playM3U8WithURL:(NSString *)url {
    [self stop]; // 停止当前播放
    
    self.isLocalPlayback = NO;
    self.originalURL = url;
    NSLog(@"[M3U8Player] 开始播放: %@", url);
    
    // 使用自定义scheme来确保资源加载器被触发
    NSString *customSchemeURL = [url stringByReplacingOccurrencesOfString:@"https://" withString:@"m3u8-custom://"];
    NSLog(@"[M3U8Player] 使用自定义scheme: %@", customSchemeURL);
    
    // 创建Asset和PlayerItem
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL URLWithString:customSchemeURL] options:nil];
    [self.keyManager setupResourceLoaderForAsset:asset];
    
    NSLog(@"[M3U8Player] Asset创建完成，URL: %@", asset.URL);
    
    self.currentItem = [[AVPlayerItem alloc] initWithAsset:asset];
    [self.currentItem setCanUseNetworkResourcesForLiveStreamingWhilePaused:YES];
    
    // 添加PlayerItem状态监听
    [self.currentItem addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    // 创建播放器
    self.player = [AVPlayer playerWithPlayerItem:self.currentItem];
    
    // 添加播放器状态监听
    [self.player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
    
    NSLog(@"[M3U8Player] 播放器和PlayerItem创建完成");
}

- (void)playLocalM3U8WithPath:(NSString *)path {
    [self stop]; // 停止当前播放
    
    self.isLocalPlayback = YES;
    NSLog(@"[M3U8Player] 开始播放本地文件: %@", path);
    
    // 创建本地Asset
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL fileURLWithPath:path] options:nil];
    
    // 为本地播放设置资源加载器，以处理密钥请求
    [self.keyManager setupResourceLoaderForLocalAsset:asset];
    
    self.currentItem = [[AVPlayerItem alloc] initWithAsset:asset];
    self.player = [AVPlayer playerWithPlayerItem:self.currentItem];
    
    // 添加状态监听
    [self.player addObserver:self forKeyPath:@"status" options:NSKeyValueObservingOptionNew context:nil];
}

- (void)stop {
    if (self.player) {
        [self.player pause];
        @try {
            [self.player removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
            NSLog(@"[M3U8Player] 移除播放器观察者异常: %@", exception.reason);
        }
        self.player = nil;
    }
    
    if (self.currentItem) {
        @try {
            [self.currentItem removeObserver:self forKeyPath:@"status"];
        } @catch (NSException *exception) {
            NSLog(@"[M3U8Player] 移除PlayerItem观察者异常: %@", exception.reason);
        }
        self.currentItem = nil;
    }
    
    [self removePlayerLayer];
}

- (void)pause {
    [self.player pause];
}

- (void)resume {
    [self.player play];
}

- (void)setupPlayerLayerInView:(UIView *)view {
    [self removePlayerLayer];
    
    if (self.player) {
        NSLog(@"[M3U8Player] 设置播放器图层，视图尺寸: %@", NSStringFromCGRect(view.bounds));
        
        self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
        self.playerLayer.contentsScale = [UIScreen mainScreen].scale;
        self.playerLayer.frame = view.bounds;
        
        // 确保在主线程中添加图层
        dispatch_async(dispatch_get_main_queue(), ^{
            [view.layer insertSublayer:self.playerLayer atIndex:0];
            NSLog(@"[M3U8Player] 播放器图层已添加到视图");
        });
    } else {
        NSLog(@"[M3U8Player] 警告：播放器为空，无法设置图层");
    }
}

- (void)removePlayerLayer {
    if (self.playerLayer) {
        [self.playerLayer removeFromSuperlayer];
        self.playerLayer = nil;
    }
}

- (AVPlayerStatus)currentStatus {
    return self.player ? self.player.status : AVPlayerStatusUnknown;
}

#pragma mark - KVO

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary<NSString *,id> *)change context:(void *)context {
    if ([keyPath isEqualToString:@"status"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (object == self.player) {
                AVPlayerStatus status = self.player.status;
                NSLog(@"[M3U8Player] 播放器状态改变: %ld", (long)status);
                
                // 通知代理状态改变
                if ([self.delegate respondsToSelector:@selector(m3u8Player:statusDidChange:)]) {
                    [self.delegate m3u8Player:self statusDidChange:status];
                }
                
                switch (status) {
                    case AVPlayerStatusReadyToPlay:
                        NSLog(@"[M3U8Player] 播放器准备完毕，开始播放");
                        [self.player play];
                        break;
                    case AVPlayerStatusFailed:
                        NSLog(@"[M3U8Player] 播放器失败: %@", self.player.error);
                        if ([self.delegate respondsToSelector:@selector(m3u8Player:didFailWithError:)]) {
                            [self.delegate m3u8Player:self didFailWithError:self.player.error];
                        }
                        break;
                    case AVPlayerStatusUnknown:
                        NSLog(@"[M3U8Player] 播放器状态未知");
                        break;
                }
            } else if (object == self.currentItem) {
                AVPlayerItemStatus status = self.currentItem.status;
                NSLog(@"[M3U8Player] PlayerItem状态改变: %ld", (long)status);
                
                switch (status) {
                    case AVPlayerItemStatusReadyToPlay:
                        NSLog(@"[M3U8Player] PlayerItem准备完毕");
                        break;
                    case AVPlayerItemStatusFailed:
                        NSLog(@"[M3U8Player] PlayerItem失败: %@", self.currentItem.error);
                        if ([self.delegate respondsToSelector:@selector(m3u8Player:didFailWithError:)]) {
                            [self.delegate m3u8Player:self didFailWithError:self.currentItem.error];
                        }
                        break;
                    case AVPlayerItemStatusUnknown:
                        NSLog(@"[M3U8Player] PlayerItem状态未知");
                        break;
                }
            }
        });
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

#pragma mark - M3U8PlayerDelegate Forwarding

- (void)m3u8Player:(M3U8Player *)player willRequestKeyForURL:(NSString *)keyURL {
    if ([self.delegate respondsToSelector:@selector(m3u8Player:willRequestKeyForURL:)]) {
        [self.delegate m3u8Player:self willRequestKeyForURL:keyURL];
    }
}

- (void)m3u8Player:(M3U8Player *)player didReceiveKeyData:(NSData *)keyData forURL:(NSString *)keyURL {
    if ([self.delegate respondsToSelector:@selector(m3u8Player:didReceiveKeyData:forURL:)]) {
        [self.delegate m3u8Player:self didReceiveKeyData:keyData forURL:keyURL];
    }
}

- (void)m3u8Player:(M3U8Player *)player didFailToLoadKeyForURL:(NSString *)keyURL error:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(m3u8Player:didFailToLoadKeyForURL:error:)]) {
        [self.delegate m3u8Player:self didFailToLoadKeyForURL:keyURL error:error];
    }
}

- (M3U8AuthConfig *)m3u8Player:(M3U8Player *)player authConfigForKeyURL:(NSString *)keyURL {
    if ([self.delegate respondsToSelector:@selector(m3u8Player:authConfigForKeyURL:)]) {
        return [self.delegate m3u8Player:self authConfigForKeyURL:keyURL];
    }
    return nil;
}

#pragma mark - Key Storage

- (void)storeKeyData:(NSData *)keyData forIdentifier:(NSString *)identifier {
    [self.keyManager storeKeyData:keyData forIdentifier:identifier];
}

- (NSData *)getStoredKeyDataForIdentifier:(NSString *)identifier {
    return [self.keyManager getStoredKeyDataForIdentifier:identifier];
}

- (void)dealloc {
    [self stop];
}

@end
