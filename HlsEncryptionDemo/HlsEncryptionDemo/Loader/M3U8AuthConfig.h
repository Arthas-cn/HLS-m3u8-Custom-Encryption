//
//  M3U8AuthConfig.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * M3U8授权配置类
 * 用于配置播放加密M3U8视频时需要的授权参数
 */
@interface M3U8AuthConfig : NSObject

// 新增encrypt_token支持
@property (nonatomic, strong) NSString *encryptToken;

/**
 * 创建默认测试配置
 */
+ (instancetype)defaultTestConfig;

/**
 * 创建基于encrypt_token的配置
 */
+ (instancetype)configWithEncryptToken:(NSString *)encryptToken;

/**
 * 生成授权参数字符串
 */
- (NSString *)authParamsString;

@end

NS_ASSUME_NONNULL_END
