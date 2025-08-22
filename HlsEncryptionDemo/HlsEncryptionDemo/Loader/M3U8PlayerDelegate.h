//
//  M3U8PlayerDelegate.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@class M3U8Player;
@class M3U8AuthConfig;

NS_ASSUME_NONNULL_BEGIN

/**
 * M3U8播放器代理协议
 */
@protocol M3U8PlayerDelegate <NSObject>

@optional

/**
 * 播放状态改变
 */
- (void)m3u8Player:(M3U8Player *)player statusDidChange:(AVPlayerStatus)status;

/**
 * 播放失败
 */
- (void)m3u8Player:(M3U8Player *)player didFailWithError:(NSError *)error;

/**
 * 密钥请求开始
 */
- (void)m3u8Player:(M3U8Player *)player willRequestKeyForURL:(NSString *)keyURL;

/**
 * 密钥请求成功
 */
- (void)m3u8Player:(M3U8Player *)player didReceiveKeyData:(NSData *)keyData forURL:(NSString *)keyURL;

/**
 * 密钥请求失败
 */
- (void)m3u8Player:(M3U8Player *)player didFailToLoadKeyForURL:(NSString *)keyURL error:(NSError *)error;

/**
 * 动态获取授权配置（可选，如果实现此方法，会覆盖静态配置）
 */
- (M3U8AuthConfig *)m3u8Player:(M3U8Player *)player authConfigForKeyURL:(NSString *)keyURL;

@end

/**
 * M3U8下载代理协议
 */
@protocol M3U8DownloaderDelegate <NSObject>

@optional

/**
 * 下载进度更新
 */
- (void)m3u8Downloader:(id)downloader downloadProgress:(float)progress;

/**
 * 下载完成
 */
- (void)m3u8Downloader:(id)downloader didFinishDownloadingToPath:(NSString *)path;

/**
 * 下载失败
 */
- (void)m3u8Downloader:(id)downloader didFailWithError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
