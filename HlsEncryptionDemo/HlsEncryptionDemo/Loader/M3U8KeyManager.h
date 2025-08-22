//
//  M3U8KeyManager.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import "M3U8AuthConfig.h"
#import "M3U8PlayerDelegate.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * M3U8密钥管理器
 * 负责拦截和处理HLS视频的密钥请求
 */
@interface M3U8KeyManager : NSObject <AVAssetResourceLoaderDelegate>

@property (nonatomic, weak) id<M3U8PlayerDelegate> delegate;
@property (nonatomic, strong) M3U8AuthConfig *authConfig;

/**
 * 单例
 */
+ (instancetype)sharedManager;

/**
 * 配置授权信息
 */
- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig;

/**
 * 为Asset设置资源加载代理
 */
- (void)setupResourceLoaderForAsset:(AVURLAsset *)asset;

/**
 * 为Asset设置资源加载代理（本地播放）
 */
- (void)setupResourceLoaderForLocalAsset:(AVURLAsset *)asset;

/**
 * 存储密钥到本地（供离线播放使用）
 */
- (void)storeKeyData:(NSData *)keyData forIdentifier:(NSString *)identifier;

/**
 * 获取本地存储的密钥
 */
- (NSData * _Nullable)getStoredKeyDataForIdentifier:(NSString *)identifier;

@end

NS_ASSUME_NONNULL_END
