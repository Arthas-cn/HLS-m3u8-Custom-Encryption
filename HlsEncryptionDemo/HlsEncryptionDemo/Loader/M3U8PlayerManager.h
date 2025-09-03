//
//  M3U8PlayerManager.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "M3U8Models.h"
#import "M3U8AuthConfig.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * 播放器管理器代理协议
 */
@protocol M3U8PlayerManagerDelegate <NSObject>

@optional
/**
 * 主M3U8解析完成
 */
- (void)playerManager:(id)manager didLoadMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 子流选择完成
 */
- (void)playerManager:(id)manager didSelectStream:(StreamInfo *)stream forQuality:(NSString *)quality;

/**
 * 媒体播放列表解析完成
 */
- (void)playerManager:(id)manager didLoadMediaPlaylist:(MediaPlaylist *)mediaPlaylist;

/**
 * 缓存状态通知
 */
- (void)playerManager:(id)manager cacheHitForURL:(NSString *)url;
- (void)playerManager:(id)manager cacheMissForURL:(NSString *)url;

/**
 * 播放器状态变化
 */
- (void)playerManager:(id)manager playerDidChangeState:(AVPlayerItemStatus)status;

/**
 * 错误通知
 */
- (void)playerManager:(id)manager didFailWithError:(NSError *)error;

@end

/**
 * M3U8播放器管理器
 * 集成所有模块，提供完整的M3U8播放功能
 */
@interface M3U8PlayerManager : NSObject

@property (nonatomic, weak) id<M3U8PlayerManagerDelegate> delegate;
@property (nonatomic, strong, readonly) AVPlayer *player;
@property (nonatomic, strong, readonly) MasterPlaylist *currentMasterPlaylist;
@property (nonatomic, strong, readonly) StreamInfo *currentStream;
@property (nonatomic, strong, readonly) MediaPlaylist *currentMediaPlaylist;

/**
 * 获取共享实例
 */
+ (instancetype)sharedManager;

/**
 * 配置授权信息
 */
- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig;

/**
 * 播放M3U8视频
 * @param url M3U8播放地址
 * @param preferredQuality 偏好清晰度 ("标清"/"高清"/"超清"/"蓝光")
 */
- (void)playVideoWithURL:(NSString *)url preferredQuality:(NSString *)preferredQuality;

/**
 * 切换清晰度
 */
- (void)switchToQuality:(NSString *)quality;

/**
 * 暂停播放
 */
- (void)pause;

/**
 * 继续播放
 */
- (void)resume;

/**
 * 停止播放
 */
- (void)stop;

/**
 * 获取所有可用的清晰度
 */
- (NSArray<NSString *> *)availableQualities;

/**
 * 获取缓存统计信息
 */
- (NSDictionary *)cacheStatistics;

/**
 * 清理缓存
 */
- (void)clearCache;

@end

NS_ASSUME_NONNULL_END
