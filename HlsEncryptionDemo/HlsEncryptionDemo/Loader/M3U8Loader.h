//
//  M3U8Loader.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "M3U8AuthConfig.h"

NS_ASSUME_NONNULL_BEGIN

@class M3U8Loader;

/**
 * M3U8加载器代理协议
 */
@protocol M3U8LoaderDelegate <NSObject>

@optional
/**
 * M3U8文件加载成功
 * @param loader 加载器实例
 * @param content M3U8文件内容
 * @param url 请求的URL
 */
- (void)loader:(M3U8Loader *)loader didLoadContent:(NSString *)content fromURL:(NSString *)url;

/**
 * M3U8文件加载失败
 * @param loader 加载器实例
 * @param error 错误信息
 * @param url 请求的URL
 */
- (void)loader:(M3U8Loader *)loader didFailWithError:(NSError *)error forURL:(NSString *)url;

/**
 * M3U8文件加载进度
 * @param loader 加载器实例
 * @param progress 进度 (0.0 - 1.0)
 * @param url 请求的URL
 */
- (void)loader:(M3U8Loader *)loader downloadProgress:(float)progress forURL:(NSString *)url;

/**
 * 缓存命中通知
 * @param loader 加载器实例
 * @param url 请求的URL
 */
- (void)loader:(M3U8Loader *)loader cacheHitForURL:(NSString *)url;

/**
 * 缓存未命中通知
 * @param loader 加载器实例
 * @param url 请求的URL
 */
- (void)loader:(M3U8Loader *)loader cacheMissForURL:(NSString *)url;

@end

/**
 * M3U8文件专用下载管理器
 * 负责所有M3U8文件的网络下载、缓存管理和错误处理
 */
@interface M3U8Loader : NSObject

@property (nonatomic, weak) id<M3U8LoaderDelegate> delegate;


/**
 * 配置授权信息
 * @param authConfig 授权配置
 */
- (void)configureWithAuthConfig:(M3U8AuthConfig * _Nullable)authConfig;

/**
 * 加载M3U8文件
 * @param url M3U8文件URL
 */
- (void)loadM3U8WithURL:(NSString *)url;

/**
 * 加载M3U8文件（带完成回调）
 * @param url M3U8文件URL
 * @param completion 完成回调
 */
- (void)loadM3U8WithURL:(NSString *)url 
             completion:(void(^)(NSString * _Nullable content, NSError * _Nullable error))completion;

/**
 * 取消指定URL的加载请求
 * @param url 要取消的URL
 */
- (void)cancelLoadForURL:(NSString *)url;

/**
 * 取消所有正在进行的加载请求
 */
- (void)cancelAllLoads;

/**
 * 清理缓存
 */
- (void)clearCache;

/**
 * 获取缓存统计信息
 */
- (NSDictionary *)cacheStatistics;

/**
 * 组件版本
 */
+ (NSString *)version;

@end

NS_ASSUME_NONNULL_END
