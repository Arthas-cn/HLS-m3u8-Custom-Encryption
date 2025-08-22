//
//  M3U8Player.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <UIKit/UIKit.h>
#import "M3U8AuthConfig.h"
#import "M3U8PlayerDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * M3U8播放器组件
 * 支持加密M3U8视频的播放，自动处理密钥认证
 */
@interface M3U8Player : NSObject

@property (nonatomic, weak) id<M3U8PlayerDelegate> delegate;
@property (nonatomic, strong, readonly) AVPlayer *player;
@property (nonatomic, strong, readonly) AVPlayerLayer *playerLayer;
@property (nonatomic, strong) M3U8AuthConfig *authConfig;

/**
 * 初始化播放器
 */
- (instancetype)initWithAuthConfig:(M3U8AuthConfig * _Nullable)authConfig;

/**
 * 播放网络M3U8视频
 */
- (void)playM3U8WithURL:(NSString *)url;

/**
 * 播放本地M3U8视频
 */
- (void)playLocalM3U8WithPath:(NSString *)path;

/**
 * 停止播放
 */
- (void)stop;

/**
 * 暂停播放
 */
- (void)pause;

/**
 * 继续播放
 */
- (void)resume;

/**
 * 设置播放视图
 */
- (void)setupPlayerLayerInView:(UIView *)view;

/**
 * 移除播放视图
 */
- (void)removePlayerLayer;

/**
 * 获取当前播放状态
 */
- (AVPlayerStatus)currentStatus;

@end

NS_ASSUME_NONNULL_END
