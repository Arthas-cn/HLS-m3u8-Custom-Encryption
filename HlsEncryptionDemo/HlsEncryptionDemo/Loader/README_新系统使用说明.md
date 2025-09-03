# M3U8新系统使用说明

## 概述

全新的M3U8播放系统已经实现，包含完整的缓存策略、解析器、清晰度选择等功能。

## 核心组件

### 1. 数据模型 (`M3U8Models.h`)
- **MasterPlaylist**: 主M3U8信息类
- **StreamInfo**: 子流信息类  
- **MediaPlaylist**: 媒体播放列表类
- **SegmentInfo**: TS片段信息类
- **EncryptionInfo**: 加密信息类

### 2. 缓存系统
- **CacheConfig**: 缓存配置类（静态配置）
- **CacheManager**: 缓存管理器（LRU策略）

### 3. 解析器
- **M3U8Parser**: M3U8解析器（支持异步解析）

### 4. 清晰度选择器
- **QualitySelector**: 清晰度选择器（智能选择策略）

### 5. 播放器管理器
- **M3U8PlayerManager**: 主要入口类（集成所有功能）

## 快速开始

### 1. 基本使用

```objc
#import "Loader/M3U8NewSystem.h"

// 初始化播放器管理器
M3U8PlayerManager *playerManager = [M3U8PlayerManager sharedManager];
playerManager.delegate = self;

// 配置授权信息
M3U8AuthConfig *authConfig = [M3U8AuthConfig defaultTestConfig];
[playerManager configureWithAuthConfig:authConfig];

// 开始播放
NSString *videoURL = @"https://example.com/video.m3u8";
[playerManager playVideoWithURL:videoURL preferredQuality:@"高清"];
```

### 2. 代理方法实现

```objc
#pragma mark - M3U8PlayerManagerDelegate

- (void)playerManager:(id)manager didLoadMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    NSLog(@"主播放列表加载完成，包含%lu个流", (unsigned long)masterPlaylist.streams.count);
}

- (void)playerManager:(id)manager didSelectStream:(StreamInfo *)stream forQuality:(NSString *)quality {
    NSLog(@"选择了%@清晰度：%@", quality, stream);
}

- (void)playerManager:(id)manager playerDidChangeState:(AVPlayerItemStatus)status {
    if (status == AVPlayerItemStatusReadyToPlay) {
        // 设置播放器图层
        AVPlayerLayer *playerLayer = [AVPlayerLayer playerLayerWithPlayer:manager.player];
        playerLayer.frame = self.videoView.bounds;
        [self.videoView.layer addSublayer:playerLayer];
    }
}

- (void)playerManager:(id)manager cacheHitForURL:(NSString *)url {
    NSLog(@"缓存命中：%@", url);
}
```

## 高级功能

### 1. 切换清晰度

```objc
// 获取可用清晰度
NSArray *qualities = [playerManager availableQualities];

// 切换到指定清晰度
[playerManager switchToQuality:@"超清"];
```

### 2. 缓存管理

```objc
// 获取缓存统计
NSDictionary *stats = [playerManager cacheStatistics];
NSLog(@"缓存信息：%@", stats);

// 清空缓存
[playerManager clearCache];
```

### 3. 播放控制

```objc
// 暂停
[playerManager pause];

// 继续
[playerManager resume];

// 停止
[playerManager stop];
```

## 清晰度等级标准

- **标清**: 分辨率 ≤ 480p，带宽 ≤ 500kbps
- **高清**: 分辨率 480p-720p，带宽 500kbps-1Mbps
- **超清**: 分辨率 720p-1080p，带宽 1Mbps-2Mbps
- **蓝光**: 分辨率 ≥ 1080p，带宽 ≥ 2Mbps

## 缓存配置

默认配置：
- 最大文件数：1000
- 最大内存占用：20MB
- 缓存有效期：60分钟
- 缓存目录：Documents/M3U8Cache/

## 系统信息

```objc
// 获取系统版本信息
NSString *version = [M3U8NewSystem version];
NSDictionary *systemInfo = [M3U8NewSystem systemInfo];
NSLog(@"M3U8新系统版本：%@", version);
NSLog(@"系统信息：%@", systemInfo);
```

## 注意事项

1. **线程安全**: 所有缓存操作和网络请求都是线程安全的
2. **错误处理**: 所有错误都会通过代理方法通知
3. **自动清理**: 缓存会自动清理过期文件和执行LRU淘汰
4. **兼容性**: 系统向下兼容现有的授权配置和密钥管理

## 示例项目

参考 `DemoViewController.m` 查看完整的使用示例。

## 技术支持

如有问题，请参考系统设计文档或联系开发团队。
