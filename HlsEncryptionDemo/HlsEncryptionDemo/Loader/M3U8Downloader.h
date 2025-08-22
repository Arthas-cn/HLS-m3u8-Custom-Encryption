//
//  M3U8Downloader.h
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
 * M3U8下载管理器
 * 负责下载加密的M3U8视频到本地
 */
@interface M3U8Downloader : NSObject

@property (nonatomic, weak) id<M3U8DownloaderDelegate> delegate;
@property (nonatomic, strong) M3U8AuthConfig *authConfig;
@property (nonatomic, readonly) BOOL isDownloading;

/**
 * 单例
 */
+ (instancetype)sharedDownloader;

/**
 * 配置授权信息
 */
- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig;

/**
 * 开始下载M3U8视频
 */
- (void)downloadM3U8WithURL:(NSString *)url;

/**
 * 取消下载
 */
- (void)cancelDownload;

/**
 * 获取下载进度
 */
- (float)downloadProgress;

@end

NS_ASSUME_NONNULL_END
