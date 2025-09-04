//
//  M3U8AuthConfig.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8AuthConfig.h"

@implementation M3U8AuthConfig

+ (instancetype)defaultTestConfig {
    // 使用文档中提供的测试encrypt_token
    return [self configWithEncryptToken:@"1756963506.1071.1.a175be5f505a22e190f6abe9fd4d7a0c"];
}


+ (instancetype)configWithEncryptToken:(NSString *)encryptToken {
    M3U8AuthConfig *config = [[M3U8AuthConfig alloc] init];
    config.encryptToken = encryptToken;
    return config;
}

- (NSString *)authParamsString {
    // 优先使用encrypt_token参数格式
    return [NSString stringWithFormat:@"encrypt_token=%@", self.encryptToken ?: @""];
}

@end
