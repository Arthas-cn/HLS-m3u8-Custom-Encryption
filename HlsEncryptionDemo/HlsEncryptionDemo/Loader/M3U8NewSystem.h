//
//  M3U8NewSystem.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN


/**
 * 新M3U8系统版本信息
 */
@interface M3U8NewSystem : NSObject

/**
 * 获取系统版本
 */
+ (NSString *)version;

/**
 * 获取系统信息
 */
+ (NSDictionary *)systemInfo;

@end

NS_ASSUME_NONNULL_END
