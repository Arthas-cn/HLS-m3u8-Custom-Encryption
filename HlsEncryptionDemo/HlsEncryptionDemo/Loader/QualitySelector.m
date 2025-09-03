//
//  QualitySelector.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "QualitySelector.h"

@implementation QualitySelector

#pragma mark - Public Methods

- (StreamInfo *)selectStreamForQuality:(NSString *)preferredQuality 
                      fromMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    if (!masterPlaylist || masterPlaylist.streams.count == 0) {
        NSLog(@"[QualitySelector] 主播放列表为空或无可用流");
        return nil;
    }
    
    StreamInfo *selectedStream = [masterPlaylist selectStreamForQuality:preferredQuality];
    
    if (selectedStream) {
        NSLog(@"[QualitySelector] 为偏好清晰度'%@'选择了流: %@", preferredQuality, selectedStream);
        
        // 通知代理
        if ([self.delegate respondsToSelector:@selector(qualitySelector:didSelectStream:forQuality:)]) {
            [self.delegate qualitySelector:self didSelectStream:selectedStream forQuality:preferredQuality];
        }
    } else {
        NSLog(@"[QualitySelector] 未找到符合偏好清晰度'%@'的流", preferredQuality);
        
        NSError *error = [NSError errorWithDomain:@"QualitySelectorError" 
                                             code:2001 
                                         userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"未找到符合偏好清晰度'%@'的流", preferredQuality]}];
        
        if ([self.delegate respondsToSelector:@selector(qualitySelector:didFailToSelectQuality:withError:)]) {
            [self.delegate qualitySelector:self didFailToSelectQuality:preferredQuality withError:error];
        }
    }
    
    return selectedStream;
}

- (StreamInfo *)selectOptimalStreamForBandwidth:(NSInteger)availableBandwidth 
                              preferredResolution:(NSString *)preferredResolution 
                                 fromMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    if (!masterPlaylist || masterPlaylist.streams.count == 0) {
        NSLog(@"[QualitySelector] 主播放列表为空或无可用流");
        return nil;
    }
    
    NSArray<StreamInfo *> *availableStreams = masterPlaylist.streams;
    StreamInfo *bestStream = nil;
    NSInteger bestScore = -1;
    
    for (StreamInfo *stream in availableStreams) {
        NSInteger score = [self calculateScoreForStream:stream 
                                      availableBandwidth:availableBandwidth 
                                     preferredResolution:preferredResolution];
        
        if (score > bestScore) {
            bestScore = score;
            bestStream = stream;
        }
    }
    
    if (bestStream) {
        NSLog(@"[QualitySelector] 根据带宽%ldkbps选择了最佳流: %@", (long)availableBandwidth, bestStream);
        
        // 通知代理
        if ([self.delegate respondsToSelector:@selector(qualitySelector:didSelectStream:forQuality:)]) {
            [self.delegate qualitySelector:self didSelectStream:bestStream forQuality:[bestStream qualityLevel]];
        }
    } else {
        NSLog(@"[QualitySelector] 未找到合适的流");
    }
    
    return bestStream;
}

- (NSArray<NSString *> *)availableQualityLevelsFromMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    if (!masterPlaylist) {
        return @[];
    }
    
    return [masterPlaylist availableQualityLevels];
}

- (BOOL)isQualityAvailable:(NSString *)quality inMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    NSArray *availableQualities = [self availableQualityLevelsFromMasterPlaylist:masterPlaylist];
    return [availableQualities containsObject:quality];
}

- (NSDictionary *)qualityDetailsForLevel:(NSString *)quality fromMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    if (!masterPlaylist) {
        return @{};
    }
    
    NSMutableArray *streamsForQuality = [[NSMutableArray alloc] init];
    NSInteger minBandwidth = NSIntegerMax;
    NSInteger maxBandwidth = 0;
    NSMutableSet *resolutions = [[NSMutableSet alloc] init];
    NSMutableSet *codecs = [[NSMutableSet alloc] init];
    
    for (StreamInfo *stream in masterPlaylist.streams) {
        if ([[stream qualityLevel] isEqualToString:quality]) {
            [streamsForQuality addObject:stream];
            
            minBandwidth = MIN(minBandwidth, stream.bandwidth);
            maxBandwidth = MAX(maxBandwidth, stream.bandwidth);
            
            if (stream.resolution.length > 0) {
                [resolutions addObject:stream.resolution];
            }
            if (stream.codecs.length > 0) {
                [codecs addObject:stream.codecs];
            }
        }
    }
    
    if (streamsForQuality.count == 0) {
        return @{};
    }
    
    return @{
        @"quality": quality,
        @"streamCount": @(streamsForQuality.count),
        @"minBandwidth": @(minBandwidth),
        @"maxBandwidth": @(maxBandwidth),
        @"bandwidthRange": [NSString stringWithFormat:@"%ld-%ld kbps", (long)(minBandwidth/1000), (long)(maxBandwidth/1000)],
        @"resolutions": [resolutions allObjects],
        @"codecs": [codecs allObjects]
    };
}

#pragma mark - Private Methods

- (NSInteger)calculateScoreForStream:(StreamInfo *)stream 
                   availableBandwidth:(NSInteger)availableBandwidth 
                  preferredResolution:(NSString *)preferredResolution {
    NSInteger score = 0;
    NSInteger streamBandwidthKbps = stream.bandwidth / 1000;
    
    // 1. 带宽适应性评分 (权重: 40%)
    if (streamBandwidthKbps <= availableBandwidth) {
        // 在可用带宽范围内，优先选择接近上限的
        CGFloat bandwidthRatio = (CGFloat)streamBandwidthKbps / availableBandwidth;
        score += (NSInteger)(bandwidthRatio * 400); // 最高400分
    } else {
        // 超出可用带宽，大幅降分
        CGFloat excessRatio = (CGFloat)streamBandwidthKbps / availableBandwidth - 1.0;
        score -= (NSInteger)(excessRatio * 200); // 惩罚分
    }
    
    // 2. 清晰度等级评分 (权重: 30%)
    NSString *qualityLevel = [stream qualityLevel];
    if ([qualityLevel isEqualToString:@"蓝光"]) {
        score += 300;
    } else if ([qualityLevel isEqualToString:@"超清"]) {
        score += 250;
    } else if ([qualityLevel isEqualToString:@"高清"]) {
        score += 200;
    } else if ([qualityLevel isEqualToString:@"标清"]) {
        score += 150;
    }
    
    // 3. 分辨率匹配评分 (权重: 20%)
    if (preferredResolution && [stream.resolution isEqualToString:preferredResolution]) {
        score += 200; // 精确匹配加分
    }
    
    // 4. 帧率评分 (权重: 10%)
    if (stream.frameRate >= 30.0) {
        score += 100;
    } else if (stream.frameRate >= 25.0) {
        score += 80;
    } else if (stream.frameRate >= 24.0) {
        score += 60;
    }
    
    NSLog(@"[QualitySelector] 流评分: %@ -> %ld分", stream, (long)score);
    return score;
}

@end
