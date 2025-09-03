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
    // 清晰度等级标准：
    // 标清：分辨率 ≤ 480p，带宽 ≤ 500kbps
    // 高清：分辨率 480p-720p，带宽 500kbps-1Mbps  
    // 超清：分辨率 720p-1080p，带宽 1Mbps-2Mbps
    // 蓝光：分辨率 ≥ 1080p，带宽 ≥ 2Mbps
    
    NSInteger bandwidthKbps = self.bandwidth / 1000; // 转换为kbps
    NSInteger heightP = self.height;
    
    if (heightP >= 1080 && bandwidthKbps >= 2000) {
        return @"蓝光";
    } else if (heightP > 720 && heightP < 1080 && bandwidthKbps >= 1000 && bandwidthKbps < 2000) {
        return @"超清";
    } else if (heightP > 480 && heightP <= 720 && bandwidthKbps >= 500 && bandwidthKbps < 1000) {
        return @"高清";
    } else {
        return @"标清";
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"StreamInfo: %@ (%@), bandwidth=%ld, resolution=%@, frameRate=%.1f, url=%@", 
            [self qualityLevel], self.codecs, (long)self.bandwidth, self.resolution, self.frameRate, self.url];
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
    
    // 首先尝试精确匹配
    for (StreamInfo *stream in self.streams) {
        if ([[stream qualityLevel] isEqualToString:preferredQuality]) {
            return stream;
        }
    }
    
    // 如果没有精确匹配，使用降级策略
    NSArray *qualityOrder = @[@"蓝光", @"超清", @"高清", @"标清"];
    NSInteger preferredIndex = [qualityOrder indexOfObject:preferredQuality];
    
    if (preferredIndex != NSNotFound) {
        // 从首选质量开始向下查找
        for (NSInteger i = preferredIndex; i < qualityOrder.count; i++) {
            NSString *quality = qualityOrder[i];
            for (StreamInfo *stream in self.streams) {
                if ([[stream qualityLevel] isEqualToString:quality]) {
                    return stream;
                }
            }
        }
    }
    
    // 如果还是没有找到，返回第一个可用的流
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

- (NSString *)description {
    return [NSString stringWithFormat:@"MasterPlaylist: version=%ld, streams=%lu, qualities=%@", 
            (long)self.version, (unsigned long)self.streams.count, [self availableQualityLevels]];
}

@end
