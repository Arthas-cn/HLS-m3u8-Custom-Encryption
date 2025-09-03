//
//  M3U8Parser.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "M3U8Models.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * M3U8解析器协议
 */
@protocol M3U8ParserDelegate <NSObject>

@optional
/**
 * 主M3U8解析完成
 */
- (void)parser:(id)parser didParseMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 媒体播放列表解析完成
 */
- (void)parser:(id)parser didParseMediaPlaylist:(MediaPlaylist *)mediaPlaylist;

/**
 * 解析失败
 */
- (void)parser:(id)parser didFailWithError:(NSError *)error;

@end

/**
 * M3U8解析器
 * 负责解析主M3U8文件和媒体播放列表文件
 */
@interface M3U8Parser : NSObject

@property (nonatomic, weak) id<M3U8ParserDelegate> delegate;

/**
 * 解析主M3U8内容
 * @param content M3U8文件内容
 * @param baseURL 基础URL，用于解析相对路径
 * @return 解析后的MasterPlaylist对象
 */
- (MasterPlaylist * _Nullable)parseMasterPlaylist:(NSString *)content baseURL:(NSString *)baseURL;

/**
 * 解析媒体播放列表内容
 * @param content M3U8文件内容
 * @param baseURL 基础URL，用于解析相对路径
 * @return 解析后的MediaPlaylist对象
 */
- (MediaPlaylist * _Nullable)parseMediaPlaylist:(NSString *)content baseURL:(NSString *)baseURL;

/**
 * 异步解析主M3U8内容
 */
- (void)parseMasterPlaylistAsync:(NSString *)content 
                         baseURL:(NSString *)baseURL 
                      completion:(void(^)(MasterPlaylist * _Nullable playlist, NSError * _Nullable error))completion;

/**
 * 异步解析媒体播放列表内容
 */
- (void)parseMediaPlaylistAsync:(NSString *)content 
                        baseURL:(NSString *)baseURL 
                     completion:(void(^)(MediaPlaylist * _Nullable playlist, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
