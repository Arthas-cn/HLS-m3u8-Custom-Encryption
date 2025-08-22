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

@property (nonatomic, strong) NSString *authKey;
@property (nonatomic, strong) NSString *uid;
@property (nonatomic, strong) NSString *session;
@property (nonatomic, strong) NSString *sign;
@property (nonatomic, strong) NSString *theaterId;
@property (nonatomic, strong) NSString *chapterId;

/**
 * 创建默认测试配置
 */
+ (instancetype)defaultTestConfig;

/**
 * 创建自定义配置
 */
+ (instancetype)configWithAuthKey:(NSString *)authKey
                              uid:(NSString *)uid
                          session:(NSString *)session
                             sign:(NSString *)sign
                        theaterId:(NSString *)theaterId
                        chapterId:(NSString *)chapterId;

/**
 * 生成授权参数字符串
 */
- (NSString *)authParamsString;

@end

NS_ASSUME_NONNULL_END
