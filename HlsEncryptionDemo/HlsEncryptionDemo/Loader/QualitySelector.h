//
//  QualitySelector.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "M3U8Models.h"

NS_ASSUME_NONNULL_BEGIN

/**
 * 清晰度选择器协议
 */
@protocol QualitySelectorDelegate <NSObject>

@optional
/**
 * 清晰度选择确认回调
 */
- (void)qualitySelector:(id)selector didSelectStream:(StreamInfo *)stream forQuality:(NSString *)quality;

/**
 * 清晰度选择失败回调
 */
- (void)qualitySelector:(id)selector didFailToSelectQuality:(NSString *)quality withError:(NSError *)error;

@end

/**
 * 清晰度选择器
 * 根据用户偏好和可用流选择最合适的清晰度
 */
@interface QualitySelector : NSObject

@property (nonatomic, weak) id<QualitySelectorDelegate> delegate;

/**
 * 根据偏好清晰度选择流
 * @param preferredQuality 偏好清晰度 ("标清"/"高清"/"超清"/"蓝光")
 * @param masterPlaylist 主播放列表
 * @return 选择的流，如果没有合适的返回nil
 */
- (StreamInfo * _Nullable)selectStreamForQuality:(NSString *)preferredQuality 
                                fromMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 根据带宽和分辨率自动选择最佳清晰度
 * @param availableBandwidth 可用带宽（kbps）
 * @param preferredResolution 偏好分辨率（可选）
 * @param masterPlaylist 主播放列表
 * @return 选择的流
 */
- (StreamInfo * _Nullable)selectOptimalStreamForBandwidth:(NSInteger)availableBandwidth 
                                        preferredResolution:(NSString * _Nullable)preferredResolution 
                                           fromMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 获取所有可用的清晰度等级
 */
- (NSArray<NSString *> *)availableQualityLevelsFromMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 检查指定清晰度是否可用
 */
- (BOOL)isQualityAvailable:(NSString *)quality inMasterPlaylist:(MasterPlaylist *)masterPlaylist;

/**
 * 获取清晰度的详细信息
 */
- (NSDictionary *)qualityDetailsForLevel:(NSString *)quality fromMasterPlaylist:(MasterPlaylist *)masterPlaylist;

@end

NS_ASSUME_NONNULL_END
