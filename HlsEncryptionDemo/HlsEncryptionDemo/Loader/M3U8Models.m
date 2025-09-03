//
//  M3U8Models.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8Models.h"

// MARK: - EncryptionInfo Implementation
@implementation EncryptionInfo

- (instancetype)initWithMethod:(NSString *)method 
                           uri:(NSString *)uri 
                            iv:(NSString *)iv 
                     keyFormat:(NSString *)keyFormat {
    self = [super init];
    if (self) {
        _method = method;
        _uri = uri;
        _iv = iv;
        _keyFormat = keyFormat;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"EncryptionInfo: method=%@, uri=%@, iv=%@, keyFormat=%@", 
            self.method, self.uri, self.iv, self.keyFormat];
}

@end

// MARK: - SegmentInfo Implementation
@implementation SegmentInfo

- (instancetype)initWithDuration:(NSTimeInterval)duration 
                             url:(NSString *)url 
                        sequence:(NSInteger)sequence {
    self = [super init];
    if (self) {
        _duration = duration;
        _url = url;
        _sequence = sequence;
    }
    return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"SegmentInfo: duration=%.3f, sequence=%ld, url=%@", 
            self.duration, (long)self.sequence, self.url];
}

@end

// MARK: - MediaPlaylist Implementation
@implementation MediaPlaylist

- (instancetype)initWithVersion:(NSInteger)version 
                 targetDuration:(NSTimeInterval)targetDuration 
                   playlistType:(NSString *)playlistType {
    self = [super init];
    if (self) {
        _version = version;
        _targetDuration = targetDuration;
        _playlistType = playlistType;
        _segments = [[NSMutableArray alloc] init];
        _isEndList = NO;
    }
    return self;
}

- (void)addSegment:(SegmentInfo *)segment {
    NSMutableArray *mutableSegments = [self.segments mutableCopy];
    [mutableSegments addObject:segment];
    _segments = [mutableSegments copy];
}

- (NSTimeInterval)totalDuration {
    NSTimeInterval total = 0.0;
    for (SegmentInfo *segment in self.segments) {
        total += segment.duration;
    }
    return total;
}

- (void)printDetailedInfo {
    NSLog(@"[MediaPlaylist] ===== 媒体播放列表详细信息 =====");
    NSLog(@"[MediaPlaylist] 版本: %ld", (long)self.version);
    NSLog(@"[MediaPlaylist] 目标时长: %.1f秒", self.targetDuration);
    NSLog(@"[MediaPlaylist] 播放列表类型: %@", self.playlistType);
    NSLog(@"[MediaPlaylist] 总时长: %.1f秒 (%.1f分钟)", [self totalDuration], [self totalDuration] / 60.0);
    NSLog(@"[MediaPlaylist] 是否结束列表: %@", self.isEndList ? @"是" : @"否");
    
    // 加密信息
    if (self.encryptionInfo) {
        NSLog(@"[MediaPlaylist] ----- 加密信息 -----");
        NSLog(@"  - 加密方法: %@", self.encryptionInfo.method);
        NSLog(@"  - 密钥URI: %@", self.encryptionInfo.uri);
        NSLog(@"  - IV值: %@", self.encryptionInfo.iv);
        NSLog(@"  - 密钥格式: %@", self.encryptionInfo.keyFormat);
    } else {
        NSLog(@"[MediaPlaylist] 加密信息: 无加密");
    }
    
    // TS片段统计
    NSLog(@"[MediaPlaylist] ----- 片段统计 -----");
    NSLog(@"[MediaPlaylist] 片段总数: %lu", (unsigned long)self.segments.count);
    
    if (self.segments.count > 0) {
        NSTimeInterval minDuration = MAXFLOAT;
        NSTimeInterval maxDuration = 0;
        NSTimeInterval totalDuration = 0;
        
        for (SegmentInfo *segment in self.segments) {
            totalDuration += segment.duration;
            minDuration = MIN(minDuration, segment.duration);
            maxDuration = MAX(maxDuration, segment.duration);
        }
        
        NSTimeInterval avgDuration = totalDuration / self.segments.count;
        
        NSLog(@"[MediaPlaylist] 片段时长范围: %.1f - %.1f秒", minDuration, maxDuration);
        NSLog(@"[MediaPlaylist] 平均片段时长: %.1f秒", avgDuration);
        
        // 显示前几个和后几个片段
        NSInteger displayCount = MIN(3, (NSInteger)self.segments.count);
        NSLog(@"[MediaPlaylist] ----- 前%ld个片段 -----", (long)displayCount);
        for (NSInteger i = 0; i < displayCount; i++) {
            SegmentInfo *segment = self.segments[i];
            NSLog(@"  #%ld: %.1fs - %@", (long)(i + 1), segment.duration, segment.url);
        }
        
        if (self.segments.count > displayCount) {
            NSLog(@"[MediaPlaylist] ... (省略%lu个片段) ...", 
                  (unsigned long)(self.segments.count - displayCount * 2));
            
            NSLog(@"[MediaPlaylist] ----- 后%ld个片段 -----", (long)displayCount);
            for (NSInteger i = self.segments.count - displayCount; i < self.segments.count; i++) {
                SegmentInfo *segment = self.segments[i];
                NSLog(@"  #%ld: %.1fs - %@", (long)(i + 1), segment.duration, segment.url);
            }
        }
    }
    
    NSLog(@"[MediaPlaylist] ================================");
}

- (NSString *)description {
    return [NSString stringWithFormat:@"MediaPlaylist: version=%ld, targetDuration=%.1f, type=%@, segments=%lu, totalDuration=%.1f", 
            (long)self.version, self.targetDuration, self.playlistType, 
            (unsigned long)self.segments.count, [self totalDuration]];
}

@end

// MARK: - StreamInfo Implementation
@implementation StreamInfo

- (instancetype)initWithBandwidth:(NSInteger)bandwidth 
                  averageBandwidth:(NSInteger)averageBandwidth 
                            codecs:(NSString *)codecs 
                        resolution:(NSString *)resolution 
                         frameRate:(CGFloat)frameRate 
                    closedCaptions:(NSString *)closedCaptions 
                               url:(NSString *)url {
    self = [super init];
    if (self) {
        _bandwidth = bandwidth;
        _averageBandwidth = averageBandwidth;
        _codecs = codecs;
        _resolution = resolution;
        _frameRate = frameRate;
        _closedCaptions = closedCaptions;
        _url = url;
        
        // 解析分辨率
        [self parseResolution];
    }
    return self;
}

- (void)parseResolution {
    if (self.resolution && [self.resolution containsString:@"x"]) {
        NSArray *components = [self.resolution componentsSeparatedByString:@"x"];
        if (components.count == 2) {
            _width = [components[0] integerValue];
            _height = [components[1] integerValue];
        }
    }
}

- (NSString *)qualityLevel {
    // 清晰度等级标准（基于视频的有效分辨率，兼容横屏和竖屏）：
    // 标清：有效分辨率 ≤ 480p
    // 高清：有效分辨率 480p < resolution ≤ 720p
    // 超清：有效分辨率 720p < resolution ≤ 1080p  
    // 蓝光：有效分辨率 > 1080p
    
    NSInteger bandwidthKbps = self.bandwidth / 1000; // 转换为kbps
    
    // 获取有效分辨率（较小的尺寸，适用于横屏和竖屏）
    NSInteger effectiveResolution = MIN(self.width, self.height);
    
    NSLog(@"[StreamInfo] 分辨率分析: %dx%d (%@), 有效分辨率: %ldp, 带宽: %ld kbps", 
          (int)self.width, (int)self.height, [self orientation], (long)effectiveResolution, (long)bandwidthKbps);
    
    // 优先按有效分辨率判断
    if (effectiveResolution > 1080) {
        return @"蓝光";
    } else if (effectiveResolution > 720) {
        // 720p < resolution ≤ 1080p
        // 如果带宽特别高（>1.5Mbps），可能是蓝光品质
        if (bandwidthKbps >= 1500) {
            return @"蓝光";
        } else {
            return @"超清";
        }
    } else if (effectiveResolution > 480) {
        // 480p < resolution ≤ 720p
        return @"高清";
    } else {
        // resolution ≤ 480p
        return @"标清";
    }
}

#pragma mark - 视频方向判断

- (BOOL)isLandscape {
    return self.width > self.height;
}

- (BOOL)isPortrait {
    return self.height > self.width;
}

- (BOOL)isSquare {
    return self.width == self.height;
}

- (NSString *)orientation {
    if ([self isLandscape]) {
        return @"横屏";
    } else if ([self isPortrait]) {
        return @"竖屏";
    } else {
        return @"正方形";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"StreamInfo: %@ (%@, %@), bandwidth=%ld, resolution=%@, frameRate=%.1f, url=%@", 
            [self qualityLevel], [self orientation], self.codecs, (long)self.bandwidth, self.resolution, self.frameRate, self.url];
}

@end

// MARK: - MasterPlaylist Implementation
@implementation MasterPlaylist

- (instancetype)initWithVersion:(NSInteger)version {
    self = [super init];
    if (self) {
        _version = version;
        _streams = [[NSMutableArray alloc] init];
        _metadata = [[NSMutableDictionary alloc] init];
        _hasIndependentSegments = NO;
    }
    return self;
}

- (void)addStream:(StreamInfo *)stream {
    NSMutableArray *mutableStreams = [self.streams mutableCopy];
    [mutableStreams addObject:stream];
    
    // 按带宽排序（从低到高）
    [mutableStreams sortUsingComparator:^NSComparisonResult(StreamInfo *obj1, StreamInfo *obj2) {
        if (obj1.bandwidth < obj2.bandwidth) {
            return NSOrderedAscending;
        } else if (obj1.bandwidth > obj2.bandwidth) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
    
    _streams = [mutableStreams copy];
}

- (void)setMetadata:(NSString *)key value:(NSString *)value {
    [self.metadata setObject:value forKey:key];
}

- (StreamInfo *)selectStreamForQuality:(NSString *)preferredQuality {
    if (self.streams.count == 0) {
        return nil;
    }
    
    // 首先收集所有匹配指定清晰度的流
    NSMutableArray *matchedStreams = [[NSMutableArray alloc] init];
    for (StreamInfo *stream in self.streams) {
        if ([[stream qualityLevel] isEqualToString:preferredQuality]) {
            [matchedStreams addObject:stream];
        }
    }
    
    // 如果找到匹配的流，选择其中带宽最高的（品质最好的）
    if (matchedStreams.count > 0) {
        StreamInfo *bestStream = matchedStreams[0];
        for (StreamInfo *stream in matchedStreams) {
            if (stream.bandwidth > bestStream.bandwidth) {
                bestStream = stream;
            }
        }
        NSLog(@"[MasterPlaylist] 找到%lu个'%@'清晰度的流，选择带宽最高的: %.1f kbps", 
              (unsigned long)matchedStreams.count, preferredQuality, bestStream.bandwidth / 1000.0);
        return bestStream;
    }
    
    // 如果没有精确匹配，使用降级策略
    NSArray *qualityOrder = @[@"蓝光", @"超清", @"高清", @"标清"];
    NSInteger preferredIndex = [qualityOrder indexOfObject:preferredQuality];
    
    if (preferredIndex != NSNotFound) {
        // 从首选质量开始向下查找
        for (NSInteger i = preferredIndex + 1; i < qualityOrder.count; i++) {
            NSString *quality = qualityOrder[i];
            NSMutableArray *fallbackStreams = [[NSMutableArray alloc] init];
            for (StreamInfo *stream in self.streams) {
                if ([[stream qualityLevel] isEqualToString:quality]) {
                    [fallbackStreams addObject:stream];
                }
            }
            if (fallbackStreams.count > 0) {
                // 选择该清晰度下带宽最高的流
                StreamInfo *bestFallback = fallbackStreams[0];
                for (StreamInfo *stream in fallbackStreams) {
                    if (stream.bandwidth > bestFallback.bandwidth) {
                        bestFallback = stream;
                    }
                }
                NSLog(@"[MasterPlaylist] 偏好清晰度'%@'不可用，降级为'%@'", preferredQuality, quality);
                return bestFallback;
            }
        }
        
        // 如果降级都没有，尝试升级选择
        for (NSInteger i = preferredIndex - 1; i >= 0; i--) {
            NSString *quality = qualityOrder[i];
            NSMutableArray *upgradeStreams = [[NSMutableArray alloc] init];
            for (StreamInfo *stream in self.streams) {
                if ([[stream qualityLevel] isEqualToString:quality]) {
                    [upgradeStreams addObject:stream];
                }
            }
            if (upgradeStreams.count > 0) {
                // 选择该清晰度下带宽最低的流（避免过高品质）
                StreamInfo *bestUpgrade = upgradeStreams[0];
                for (StreamInfo *stream in upgradeStreams) {
                    if (stream.bandwidth < bestUpgrade.bandwidth) {
                        bestUpgrade = stream;
                    }
                }
                NSLog(@"[MasterPlaylist] 偏好清晰度'%@'不可用，升级为'%@'", preferredQuality, quality);
                return bestUpgrade;
            }
        }
    }
    
    // 如果还是没有找到，返回第一个可用的流
    NSLog(@"[MasterPlaylist] 偏好清晰度'%@'不可用，默认选择第一个流", preferredQuality);
    return self.streams.firstObject;
}

- (NSArray<NSString *> *)availableQualityLevels {
    NSMutableSet *qualities = [[NSMutableSet alloc] init];
    for (StreamInfo *stream in self.streams) {
        [qualities addObject:[stream qualityLevel]];
    }
    
    // 按质量等级排序
    NSArray *orderedQualities = @[@"蓝光", @"超清", @"高清", @"标清"];
    NSMutableArray *availableQualities = [[NSMutableArray alloc] init];
    for (NSString *quality in orderedQualities) {
        if ([qualities containsObject:quality]) {
            [availableQualities addObject:quality];
        }
    }
    
    return [availableQualities copy];
}

- (void)printDetailedInfo {
    NSLog(@"[MasterPlaylist] ===== 主播放列表详细信息 =====");
    NSLog(@"[MasterPlaylist] 版本: %ld", (long)self.version);
    NSLog(@"[MasterPlaylist] 独立片段: %@", self.hasIndependentSegments ? @"是" : @"否");
    NSLog(@"[MasterPlaylist] 可用清晰度: %@", [self availableQualityLevels]);
    NSLog(@"[MasterPlaylist] 元数据: %@", self.metadata);
    
    NSLog(@"[MasterPlaylist] ----- 流信息列表 (%lu个) -----", (unsigned long)self.streams.count);
    
    for (NSInteger i = 0; i < self.streams.count; i++) {
        StreamInfo *stream = self.streams[i];
        NSLog(@"[MasterPlaylist] 流 #%ld:", (long)(i + 1));
        NSLog(@"  - URL: %@", stream.url);
        NSLog(@"  - 清晰度: %@", [stream qualityLevel]);
        NSLog(@"  - 视频方向: %@", [stream orientation]);
        NSLog(@"  - 带宽: %ld bps (%.1f kbps)", (long)stream.bandwidth, stream.bandwidth / 1000.0);
        NSLog(@"  - 平均带宽: %ld bps (%.1f kbps)", (long)stream.averageBandwidth, stream.averageBandwidth / 1000.0);
        NSLog(@"  - 分辨率: %@ (%dx%d)", stream.resolution, (int)stream.width, (int)stream.height);
        NSLog(@"  - 帧率: %.1f fps", stream.frameRate);
        NSLog(@"  - 编解码器: %@", stream.codecs);
        NSLog(@"  - 字幕: %@", stream.closedCaptions);
        NSLog(@"  ---");
    }
    
    // 按清晰度分组统计
    NSMutableDictionary *qualityGroups = [[NSMutableDictionary alloc] init];
    for (StreamInfo *stream in self.streams) {
        NSString *quality = [stream qualityLevel];
        NSMutableArray *group = qualityGroups[quality];
        if (!group) {
            group = [[NSMutableArray alloc] init];
            qualityGroups[quality] = group;
        }
        [group addObject:stream];
    }
    
    NSLog(@"[MasterPlaylist] ----- 按清晰度分组统计 -----");
    NSArray *sortedQualities = @[@"蓝光", @"超清", @"高清", @"标清"];
    for (NSString *quality in sortedQualities) {
        NSArray *streams = qualityGroups[quality];
        if (streams.count > 0) {
            StreamInfo *minStream = streams[0];
            StreamInfo *maxStream = streams[0];
            
            for (StreamInfo *stream in streams) {
                if (stream.bandwidth < minStream.bandwidth) minStream = stream;
                if (stream.bandwidth > maxStream.bandwidth) maxStream = stream;
            }
            
            NSLog(@"[MasterPlaylist] %@: %lu个流", quality, (unsigned long)streams.count);
            NSLog(@"  - 带宽范围: %.1f - %.1f kbps", minStream.bandwidth / 1000.0, maxStream.bandwidth / 1000.0);
            NSLog(@"  - 分辨率范围: %@ - %@", minStream.resolution, maxStream.resolution);
        }
    }
    
    NSLog(@"[MasterPlaylist] ================================");
}

- (NSString *)description {
    return [NSString stringWithFormat:@"MasterPlaylist: version=%ld, streams=%lu, qualities=%@", 
            (long)self.version, (unsigned long)self.streams.count, [self availableQualityLevels]];
}

@end
