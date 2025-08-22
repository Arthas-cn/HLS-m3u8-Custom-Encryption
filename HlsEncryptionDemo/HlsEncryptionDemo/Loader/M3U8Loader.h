//
//  M3U8Loader.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

// 导入所有组件
#import "M3U8AuthConfig.h"
#import "M3U8PlayerDelegate.h"
#import "M3U8KeyManager.h"
#import "M3U8Player.h"
#import "M3U8Downloader.h"

/**
 * M3U8Loader 组件库
 * 
 * 使用示例：
 * 
 * // 1. 创建配置
 * M3U8AuthConfig *config = [M3U8AuthConfig defaultTestConfig];
 * 
 * // 2. 创建播放器
 * M3U8Player *player = [[M3U8Player alloc] initWithAuthConfig:config];
 * player.delegate = self;
 * 
 * // 3. 设置播放视图
 * [player setupPlayerLayerInView:self.view];
 * 
 * // 4. 开始播放
 * [player playM3U8WithURL:@"your_m3u8_url"];
 * 
 * // 5. 下载视频（可选）
 * M3U8Downloader *downloader = [M3U8Downloader sharedDownloader];
 * downloader.delegate = self;
 * [downloader configureWithAuthConfig:config];
 * [downloader downloadM3U8WithURL:@"your_m3u8_url"];
 */

NS_ASSUME_NONNULL_BEGIN

@interface M3U8Loader : NSObject

/**
 * 组件版本
 */
+ (NSString *)version;

@end

NS_ASSUME_NONNULL_END
