//
//  M3U8Parser.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8Parser.h"

@interface M3U8Parser ()
@property (nonatomic, strong) dispatch_queue_t parseQueue;
@end

@implementation M3U8Parser

- (instancetype)init {
    self = [super init];
    if (self) {
        _parseQueue = dispatch_queue_create("com.hlsencryption.parser", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

#pragma mark - Public Methods

- (MasterPlaylist *)parseMasterPlaylist:(NSString *)content baseURL:(NSString *)baseURL {
    if (!content || content.length == 0) {
        NSLog(@"[M3U8Parser] 主播放列表内容为空");
        return nil;
    }
    
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    MasterPlaylist *masterPlaylist = [[MasterPlaylist alloc] initWithVersion:3]; // 默认版本
    
    BOOL isValidM3U8 = NO;
    NSMutableDictionary *currentStreamInfo = nil;
    
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([trimmedLine isEqualToString:@"#EXTM3U"]) {
            isValidM3U8 = YES;
            continue;
        }
        
        if ([trimmedLine hasPrefix:@"#EXT-X-VERSION:"]) {
            NSString *versionStr = [trimmedLine substringFromIndex:[@"#EXT-X-VERSION:" length]];
            masterPlaylist.version = [versionStr integerValue];
        }
        else if ([trimmedLine isEqualToString:@"#EXT-X-INDEPENDENT-SEGMENTS"]) {
            masterPlaylist.hasIndependentSegments = YES;
        }
        else if ([trimmedLine hasPrefix:@"#EXT-X-STREAM-INF:"]) {
            currentStreamInfo = [self parseStreamInfLine:trimmedLine];
        }
        else if (currentStreamInfo && ![trimmedLine hasPrefix:@"#"] && trimmedLine.length > 0) {
            // 这是子流URL
            NSString *streamURL = [self resolveURL:trimmedLine baseURL:baseURL];
            currentStreamInfo[@"url"] = streamURL;
            
            // 创建StreamInfo对象
            StreamInfo *stream = [self createStreamInfoFromDictionary:currentStreamInfo];
            if (stream) {
                [masterPlaylist addStream:stream];
            }
            
            currentStreamInfo = nil;
        }
    }
    
    if (!isValidM3U8) {
        NSLog(@"[M3U8Parser] 无效的M3U8文件格式");
        return nil;
    }
    
    NSLog(@"[M3U8Parser] 主播放列表解析完成，包含%lu个子流", (unsigned long)masterPlaylist.streams.count);
    return masterPlaylist;
}

- (MediaPlaylist *)parseMediaPlaylist:(NSString *)content baseURL:(NSString *)baseURL {
    if (!content || content.length == 0) {
        NSLog(@"[M3U8Parser] 媒体播放列表内容为空");
        return nil;
    }
    
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    MediaPlaylist *mediaPlaylist = [[MediaPlaylist alloc] initWithVersion:3 targetDuration:10 playlistType:@"VOD"];
    
    BOOL isValidM3U8 = NO;
    NSTimeInterval currentSegmentDuration = 0;
    NSInteger segmentSequence = 0;
    
    for (NSString *line in lines) {
        NSString *trimmedLine = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        if ([trimmedLine isEqualToString:@"#EXTM3U"]) {
            isValidM3U8 = YES;
            continue;
        }
        
        if ([trimmedLine hasPrefix:@"#EXT-X-VERSION:"]) {
            NSString *versionStr = [trimmedLine substringFromIndex:[@"#EXT-X-VERSION:" length]];
            mediaPlaylist.version = [versionStr integerValue];
        }
        else if ([trimmedLine hasPrefix:@"#EXT-X-TARGETDURATION:"]) {
            NSString *durationStr = [trimmedLine substringFromIndex:[@"#EXT-X-TARGETDURATION:" length]];
            mediaPlaylist.targetDuration = [durationStr doubleValue];
        }
        else if ([trimmedLine hasPrefix:@"#EXT-X-PLAYLIST-TYPE:"]) {
            NSString *typeStr = [trimmedLine substringFromIndex:[@"#EXT-X-PLAYLIST-TYPE:" length]];
            mediaPlaylist.playlistType = typeStr;
        }
        else if ([trimmedLine hasPrefix:@"#EXT-X-KEY:"]) {
            EncryptionInfo *encryptionInfo = [self parseKeyLine:trimmedLine];
            mediaPlaylist.encryptionInfo = encryptionInfo;
        }
        else if ([trimmedLine hasPrefix:@"#EXTINF:"]) {
            NSString *infStr = [trimmedLine substringFromIndex:[@"#EXTINF:" length]];
            // 解析格式: duration,title
            NSArray *components = [infStr componentsSeparatedByString:@","];
            if (components.count > 0) {
                currentSegmentDuration = [components[0] doubleValue];
            }
        }
        else if ([trimmedLine isEqualToString:@"#EXT-X-ENDLIST"]) {
            mediaPlaylist.isEndList = YES;
        }
        else if (![trimmedLine hasPrefix:@"#"] && trimmedLine.length > 0) {
            // 这是TS片段URL
            NSString *segmentURL = [self resolveURL:trimmedLine baseURL:baseURL];
            SegmentInfo *segment = [[SegmentInfo alloc] initWithDuration:currentSegmentDuration 
                                                                     url:segmentURL 
                                                                sequence:segmentSequence++];
            [mediaPlaylist addSegment:segment];
            currentSegmentDuration = 0;
        }
    }
    
    if (!isValidM3U8) {
        NSLog(@"[M3U8Parser] 无效的M3U8文件格式");
        return nil;
    }
    
    NSLog(@"[M3U8Parser] 媒体播放列表解析完成，包含%lu个片段，总时长%.1f秒", 
          (unsigned long)mediaPlaylist.segments.count, [mediaPlaylist totalDuration]);
    return mediaPlaylist;
}

- (void)parseMasterPlaylistAsync:(NSString *)content 
                         baseURL:(NSString *)baseURL 
                      completion:(void(^)(MasterPlaylist * _Nullable playlist, NSError * _Nullable error))completion {
    dispatch_async(self.parseQueue, ^{
        @try {
            MasterPlaylist *playlist = [self parseMasterPlaylist:content baseURL:baseURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (playlist) {
                    if ([self.delegate respondsToSelector:@selector(parser:didParseMasterPlaylist:)]) {
                        [self.delegate parser:self didParseMasterPlaylist:playlist];
                    }
                    if (completion) completion(playlist, nil);
                } else {
                    NSError *error = [NSError errorWithDomain:@"M3U8ParserError" 
                                                         code:1001 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"主播放列表解析失败"}];
                    if ([self.delegate respondsToSelector:@selector(parser:didFailWithError:)]) {
                        [self.delegate parser:self didFailWithError:error];
                    }
                    if (completion) completion(nil, error);
                }
            });
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"M3U8ParserError" 
                                                     code:1002 
                                                 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"解析异常"}];
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithError:)]) {
                    [self.delegate parser:self didFailWithError:error];
                }
                if (completion) completion(nil, error);
            });
        }
    });
}

- (void)parseMediaPlaylistAsync:(NSString *)content 
                        baseURL:(NSString *)baseURL 
                     completion:(void(^)(MediaPlaylist * _Nullable playlist, NSError * _Nullable error))completion {
    dispatch_async(self.parseQueue, ^{
        @try {
            MediaPlaylist *playlist = [self parseMediaPlaylist:content baseURL:baseURL];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (playlist) {
                    if ([self.delegate respondsToSelector:@selector(parser:didParseMediaPlaylist:)]) {
                        [self.delegate parser:self didParseMediaPlaylist:playlist];
                    }
                    if (completion) completion(playlist, nil);
                } else {
                    NSError *error = [NSError errorWithDomain:@"M3U8ParserError" 
                                                         code:1003 
                                                     userInfo:@{NSLocalizedDescriptionKey: @"媒体播放列表解析失败"}];
                    if ([self.delegate respondsToSelector:@selector(parser:didFailWithError:)]) {
                        [self.delegate parser:self didFailWithError:error];
                    }
                    if (completion) completion(nil, error);
                }
            });
        } @catch (NSException *exception) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSError *error = [NSError errorWithDomain:@"M3U8ParserError" 
                                                     code:1004 
                                                 userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"解析异常"}];
                if ([self.delegate respondsToSelector:@selector(parser:didFailWithError:)]) {
                    [self.delegate parser:self didFailWithError:error];
                }
                if (completion) completion(nil, error);
            });
        }
    });
}

#pragma mark - Private Methods

- (NSMutableDictionary *)parseStreamInfLine:(NSString *)line {
    // 解析 #EXT-X-STREAM-INF: 行
    NSString *attributes = [line substringFromIndex:[@"#EXT-X-STREAM-INF:" length]];
    NSMutableDictionary *streamInfo = [[NSMutableDictionary alloc] init];
    
    // 使用正则表达式解析属性
    NSString *pattern = @"([A-Z-]+)=(?:\"([^\"]*)\"|([^,]*))";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern 
                                                                           options:0 
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:attributes 
                                      options:0 
                                        range:NSMakeRange(0, attributes.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSString *key = [attributes substringWithRange:[match rangeAtIndex:1]];
        
        NSString *value = nil;
        if ([match rangeAtIndex:2].location != NSNotFound) {
            value = [attributes substringWithRange:[match rangeAtIndex:2]]; // 引号内的值
        } else if ([match rangeAtIndex:3].location != NSNotFound) {
            value = [attributes substringWithRange:[match rangeAtIndex:3]]; // 无引号的值
        }
        
        if (key && value) {
            streamInfo[key] = value;
        }
    }
    
    return streamInfo;
}

- (EncryptionInfo *)parseKeyLine:(NSString *)line {
    // 解析 #EXT-X-KEY: 行
    NSString *attributes = [line substringFromIndex:[@"#EXT-X-KEY:" length]];
    NSMutableDictionary *keyInfo = [[NSMutableDictionary alloc] init];
    
    // 使用正则表达式解析属性
    NSString *pattern = @"([A-Z-]+)=(?:\"([^\"]*)\"|([^,]*))";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern 
                                                                           options:0 
                                                                             error:nil];
    NSArray *matches = [regex matchesInString:attributes 
                                      options:0 
                                        range:NSMakeRange(0, attributes.length)];
    
    for (NSTextCheckingResult *match in matches) {
        NSString *key = [attributes substringWithRange:[match rangeAtIndex:1]];
        
        NSString *value = nil;
        if ([match rangeAtIndex:2].location != NSNotFound) {
            value = [attributes substringWithRange:[match rangeAtIndex:2]]; // 引号内的值
        } else if ([match rangeAtIndex:3].location != NSNotFound) {
            value = [attributes substringWithRange:[match rangeAtIndex:3]]; // 无引号的值
        }
        
        if (key && value) {
            keyInfo[key] = value;
        }
    }
    
    EncryptionInfo *encryptionInfo = [[EncryptionInfo alloc] initWithMethod:keyInfo[@"METHOD"] ?: @"" 
                                                                        uri:keyInfo[@"URI"] ?: @"" 
                                                                         iv:keyInfo[@"IV"] ?: @"" 
                                                                  keyFormat:keyInfo[@"KEYFORMAT"] ?: @"identity"];
    return encryptionInfo;
}

- (StreamInfo *)createStreamInfoFromDictionary:(NSDictionary *)dict {
    NSInteger bandwidth = [dict[@"BANDWIDTH"] integerValue];
    NSInteger averageBandwidth = [dict[@"AVERAGE-BANDWIDTH"] integerValue];
    NSString *codecs = dict[@"CODECS"] ?: @"";
    NSString *resolution = dict[@"RESOLUTION"] ?: @"";
    CGFloat frameRate = [dict[@"FRAME-RATE"] floatValue];
    NSString *closedCaptions = dict[@"CLOSED-CAPTIONS"] ?: @"NONE";
    NSString *url = dict[@"url"] ?: @"";
    
    if (bandwidth == 0 || url.length == 0) {
        NSLog(@"[M3U8Parser] 子流信息不完整，跳过");
        return nil;
    }
    
    return [[StreamInfo alloc] initWithBandwidth:bandwidth 
                                averageBandwidth:averageBandwidth 
                                          codecs:codecs 
                                      resolution:resolution 
                                       frameRate:frameRate 
                                  closedCaptions:closedCaptions 
                                             url:url];
}

- (NSString *)resolveURL:(NSString *)url baseURL:(NSString *)baseURL {
    if ([url hasPrefix:@"http://"] || [url hasPrefix:@"https://"]) {
        // 绝对URL，直接返回
        return url;
    }
    
    // 相对URL，需要与baseURL拼接
    NSURL *base = [NSURL URLWithString:baseURL];
    if (!base) {
        return url;
    }
    
    NSURL *resolvedURL = [NSURL URLWithString:url relativeToURL:base];
    return resolvedURL.absoluteString ?: url;
}

@end
