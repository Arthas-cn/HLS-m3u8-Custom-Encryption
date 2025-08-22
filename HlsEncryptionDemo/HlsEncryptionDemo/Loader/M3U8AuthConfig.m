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
    return [self configWithAuthKey:@"666"
                                uid:@"test"
                            session:@"test"
                               sign:@"test"
                          theaterId:@"9032"
                          chapterId:@"1"];
}

+ (instancetype)configWithAuthKey:(NSString *)authKey
                              uid:(NSString *)uid
                          session:(NSString *)session
                             sign:(NSString *)sign
                        theaterId:(NSString *)theaterId
                        chapterId:(NSString *)chapterId {
    M3U8AuthConfig *config = [[M3U8AuthConfig alloc] init];
    config.authKey = authKey;
    config.uid = uid;
    config.session = session;
    config.sign = sign;
    config.theaterId = theaterId;
    config.chapterId = chapterId;
    return config;
}

- (NSString *)authParamsString {
    return [NSString stringWithFormat:@"auth_key=%@&uid=%@&session=%@&sign=%@&theater_id=%@&chapter_id=%@",
            self.authKey ?: @"",
            self.uid ?: @"",
            self.session ?: @"",
            self.sign ?: @"",
            self.theaterId ?: @"",
            self.chapterId ?: @""];
}

@end
