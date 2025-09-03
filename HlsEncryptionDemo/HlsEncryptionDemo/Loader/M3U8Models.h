//
//  M3U8Models.h
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// MARK: - 加密信息类
@interface EncryptionInfo : NSObject

@property (nonatomic, strong) NSString *method;        // 加密方法 (AES-128)
@property (nonatomic, strong) NSString *uri;           // 密钥URI
@property (nonatomic, strong) NSString *iv;            // IV值
@property (nonatomic, strong) NSString *keyFormat;     // 密钥格式

- (instancetype)initWithMethod:(NSString *)method 
                           uri:(NSString *)uri 
                            iv:(NSString *)iv 
                     keyFormat:(NSString *)keyFormat;

@end

// MARK: - TS片段信息类
@interface SegmentInfo : NSObject

@property (nonatomic, assign) NSTimeInterval duration; // 片段时长
@property (nonatomic, strong) NSString *url;           // 片段URL
@property (nonatomic, assign) NSInteger sequence;      // 序号

- (instancetype)initWithDuration:(NSTimeInterval)duration 
                             url:(NSString *)url 
                        sequence:(NSInteger)sequence;

@end

// MARK: - 媒体播放列表类
@interface MediaPlaylist : NSObject

@property (nonatomic, assign) NSInteger version;                       // 版本号
@property (nonatomic, assign) NSTimeInterval targetDuration;           // 目标时长
@property (nonatomic, strong) NSString *playlistType;                  // 播放列表类型 (VOD/LIVE)
@property (nonatomic, strong, nullable) EncryptionInfo *encryptionInfo; // 加密信息
@property (nonatomic, strong) NSArray<SegmentInfo *> *segments;        // TS片段列表
@property (nonatomic, assign) BOOL isEndList;                          // 是否结束列表

- (instancetype)initWithVersion:(NSInteger)version 
                 targetDuration:(NSTimeInterval)targetDuration 
                   playlistType:(NSString *)playlistType;

- (void)addSegment:(SegmentInfo *)segment;
- (NSTimeInterval)totalDuration; // 计算总时长

@end

// MARK: - 子流信息类
@interface StreamInfo : NSObject

@property (nonatomic, assign) NSInteger bandwidth;         // 带宽
@property (nonatomic, assign) NSInteger averageBandwidth;  // 平均带宽
@property (nonatomic, strong) NSString *codecs;            // 编解码器
@property (nonatomic, strong) NSString *resolution;        // 分辨率 (例: "720x1280")
@property (nonatomic, assign) CGFloat frameRate;           // 帧率
@property (nonatomic, strong) NSString *closedCaptions;    // 字幕信息
@property (nonatomic, strong) NSString *url;               // 子流URL

// 解析后的分辨率信息
@property (nonatomic, assign, readonly) NSInteger width;   // 宽度
@property (nonatomic, assign, readonly) NSInteger height;  // 高度

- (instancetype)initWithBandwidth:(NSInteger)bandwidth 
                  averageBandwidth:(NSInteger)averageBandwidth 
                            codecs:(NSString *)codecs 
                        resolution:(NSString *)resolution 
                         frameRate:(CGFloat)frameRate 
                    closedCaptions:(NSString *)closedCaptions 
                               url:(NSString *)url;

// 清晰度等级判断
- (NSString *)qualityLevel; // 返回: "标清"/"高清"/"超清"/"蓝光"

@end

// MARK: - 主M3U8信息类
@interface MasterPlaylist : NSObject

@property (nonatomic, assign) NSInteger version;                           // 版本信息
@property (nonatomic, strong) NSArray<StreamInfo *> *streams;              // 子流列表
@property (nonatomic, strong) NSMutableDictionary *metadata;               // 元数据
@property (nonatomic, assign) BOOL hasIndependentSegments;                 // 是否有独立片段

- (instancetype)initWithVersion:(NSInteger)version;

- (void)addStream:(StreamInfo *)stream;
- (void)setMetadata:(NSString *)key value:(NSString *)value;

// 根据清晰度偏好选择最合适的子流
- (StreamInfo * _Nullable)selectStreamForQuality:(NSString *)preferredQuality;

// 获取所有可用的清晰度等级
- (NSArray<NSString *> *)availableQualityLevels;

@end

NS_ASSUME_NONNULL_END
