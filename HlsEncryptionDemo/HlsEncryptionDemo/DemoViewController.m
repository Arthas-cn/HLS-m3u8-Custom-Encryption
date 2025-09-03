//
//  DemoViewController.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "DemoViewController.h"
#import "Loader/M3U8PlayerManager.h"
#import "Loader/M3U8AuthConfig.h"
#import <AVFoundation/AVFoundation.h>

@interface DemoViewController () <M3U8PlayerManagerDelegate>

// UI组件
@property (nonatomic, strong) UIView *playerView;
@property (nonatomic, strong) UIButton *playButton;
@property (nonatomic, strong) UIButton *pauseButton;
@property (nonatomic, strong) UIButton *stopButton;
@property (nonatomic, strong) UISegmentedControl *qualityControl;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *cacheLabel;
@property (nonatomic, strong) UIButton *clearCacheButton;

// 播放器管理器
@property (nonatomic, strong) M3U8PlayerManager *playerManager;
@property (nonatomic, strong) AVPlayerLayer *playerLayer;

// 测试数据
@property (nonatomic, strong) NSString *testURL;
@property (nonatomic, strong) NSArray<NSString *> *availableQualities;

@end

@implementation DemoViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"M3U8播放器演示";
    self.view.backgroundColor = [UIColor whiteColor];
    
    // 设置测试URL
    self.testURL = @"https://cdn-aws-test2.playlet.com/hls/v1/i18n/vip/1071/1/1_4434a0517b48f0b887656eba0ca0ed74.m3u8";
    
    [self setupUI];
    [self setupPlayerManager];
    [self updateCacheInfo];
}

- (void)setupUI {
    // 播放器视图
    self.playerView = [[UIView alloc] init];
    self.playerView.backgroundColor = [UIColor blackColor];
    self.playerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.playerView];
    
    // 播放按钮
    self.playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playButton setTitle:@"播放" forState:UIControlStateNormal];
    [self.playButton addTarget:self action:@selector(playAction) forControlEvents:UIControlEventTouchUpInside];
    self.playButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.playButton];
    
    // 暂停按钮
    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton setTitle:@"暂停" forState:UIControlStateNormal];
    [self.pauseButton addTarget:self action:@selector(pauseAction) forControlEvents:UIControlEventTouchUpInside];
    self.pauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.pauseButton];
    
    // 停止按钮
    self.stopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.stopButton setTitle:@"停止" forState:UIControlStateNormal];
    [self.stopButton addTarget:self action:@selector(stopAction) forControlEvents:UIControlEventTouchUpInside];
    self.stopButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.stopButton];
    
    // 清晰度选择
    self.qualityControl = [[UISegmentedControl alloc] initWithItems:@[@"标清", @"高清", @"超清", @"蓝光"]];
    self.qualityControl.selectedSegmentIndex = 1; // 默认选择高清
    [self.qualityControl addTarget:self action:@selector(qualityChanged) forControlEvents:UIControlEventValueChanged];
    self.qualityControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.qualityControl];
    
    // 状态标签
    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.text = @"状态：准备就绪";
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.statusLabel];
    
    // 缓存信息标签
    self.cacheLabel = [[UILabel alloc] init];
    self.cacheLabel.text = @"缓存信息：";
    self.cacheLabel.numberOfLines = 0;
    self.cacheLabel.font = [UIFont systemFontOfSize:12];
    self.cacheLabel.textColor = [UIColor grayColor];
    self.cacheLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.cacheLabel];
    
    // 清空缓存按钮
    self.clearCacheButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearCacheButton setTitle:@"清空缓存" forState:UIControlStateNormal];
    [self.clearCacheButton addTarget:self action:@selector(clearCacheAction) forControlEvents:UIControlEventTouchUpInside];
    self.clearCacheButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.clearCacheButton];
    
    [self setupConstraints];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // 播放器视图
        [self.playerView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:20],
        [self.playerView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.playerView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [self.playerView.heightAnchor constraintEqualToConstant:200],
        
        // 播放按钮
        [self.playButton.topAnchor constraintEqualToAnchor:self.playerView.bottomAnchor constant:20],
        [self.playButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.playButton.widthAnchor constraintEqualToConstant:60],
        
        // 暂停按钮
        [self.pauseButton.topAnchor constraintEqualToAnchor:self.playButton.topAnchor],
        [self.pauseButton.leadingAnchor constraintEqualToAnchor:self.playButton.trailingAnchor constant:20],
        [self.pauseButton.widthAnchor constraintEqualToConstant:60],
        
        // 停止按钮
        [self.stopButton.topAnchor constraintEqualToAnchor:self.playButton.topAnchor],
        [self.stopButton.leadingAnchor constraintEqualToAnchor:self.pauseButton.trailingAnchor constant:20],
        [self.stopButton.widthAnchor constraintEqualToConstant:60],
        
        // 清晰度控制
        [self.qualityControl.topAnchor constraintEqualToAnchor:self.playButton.bottomAnchor constant:20],
        [self.qualityControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.qualityControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // 状态标签
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.qualityControl.bottomAnchor constant:20],
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // 缓存标签
        [self.cacheLabel.topAnchor constraintEqualToAnchor:self.statusLabel.bottomAnchor constant:20],
        [self.cacheLabel.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [self.cacheLabel.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        
        // 清空缓存按钮
        [self.clearCacheButton.topAnchor constraintEqualToAnchor:self.cacheLabel.bottomAnchor constant:20],
        [self.clearCacheButton.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
    ]];
}

- (void)setupPlayerManager {
    // 初始化播放器管理器
    self.playerManager = [M3U8PlayerManager sharedManager];
    self.playerManager.delegate = self;
    
    // 配置授权信息
    M3U8AuthConfig *authConfig = [M3U8AuthConfig defaultTestConfig];
    [self.playerManager configureWithAuthConfig:authConfig];
    
    NSLog(@"[DemoViewController] 播放器管理器初始化完成");
}

#pragma mark - Actions

- (void)playAction {
    NSString *selectedQuality = [self getSelectedQuality];
    [self.playerManager playVideoWithURL:self.testURL preferredQuality:selectedQuality];
    [self updateStatus:@"正在加载..."];
}

- (void)pauseAction {
    [self.playerManager pause];
    [self updateStatus:@"已暂停"];
}

- (void)stopAction {
    [self.playerManager stop];
    [self removePlayerLayer];
    [self updateStatus:@"已停止"];
}

- (void)qualityChanged {
    NSString *selectedQuality = [self getSelectedQuality];
    [self.playerManager switchToQuality:selectedQuality];
    [self updateStatus:[NSString stringWithFormat:@"切换到%@", selectedQuality]];
}

- (void)clearCacheAction {
    [self.playerManager clearCache];
    [self updateCacheInfo];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                   message:@"缓存已清空" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Helper Methods

- (NSString *)getSelectedQuality {
    NSArray *qualities = @[@"标清", @"高清", @"超清", @"蓝光"];
    NSInteger selectedIndex = self.qualityControl.selectedSegmentIndex;
    if (selectedIndex >= 0 && selectedIndex < qualities.count) {
        return qualities[selectedIndex];
    }
    return @"高清";
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = [NSString stringWithFormat:@"状态：%@", status];
    });
}

- (void)updateCacheInfo {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *stats = [self.playerManager cacheStatistics];
        
        NSNumber *fileCount = stats[@"fileCount"];
        NSNumber *totalSize = stats[@"totalSize"];
        NSNumber *hitRate = stats[@"hitRate"];
        
        NSString *sizeString = @"0MB";
        if (totalSize && [totalSize unsignedIntegerValue] > 0) {
            CGFloat sizeMB = [totalSize unsignedIntegerValue] / (1024.0 * 1024.0);
            sizeString = [NSString stringWithFormat:@"%.2fMB", sizeMB];
        }
        
        self.cacheLabel.text = [NSString stringWithFormat:@"缓存：%@个文件，%@，命中率%.1f%%", 
                               fileCount ?: @0, sizeString, ([hitRate floatValue] * 100)];
    });
}

- (void)setupPlayerLayer {
    if (self.playerLayer) {
        [self.playerLayer removeFromSuperlayer];
    }
    
    self.playerLayer = [AVPlayerLayer playerLayerWithPlayer:self.playerManager.player];
    self.playerLayer.frame = self.playerView.bounds;
    self.playerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    [self.playerView.layer addSublayer:self.playerLayer];
}

- (void)removePlayerLayer {
    if (self.playerLayer) {
        [self.playerLayer removeFromSuperlayer];
        self.playerLayer = nil;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (self.playerLayer) {
        self.playerLayer.frame = self.playerView.bounds;
    }
}

#pragma mark - M3U8PlayerManagerDelegate

- (void)playerManager:(id)manager didLoadMasterPlaylist:(MasterPlaylist *)masterPlaylist {
    NSLog(@"[DemoViewController] 主播放列表加载完成，包含%lu个流", (unsigned long)masterPlaylist.streams.count);
    
    self.availableQualities = [masterPlaylist availableQualityLevels];
    [self updateStatus:[NSString stringWithFormat:@"找到%lu个清晰度选项", (unsigned long)self.availableQualities.count]];
    
    dispatch_async(dispatch_get_main_queue(), ^{
        // 更新清晰度控制器
        for (NSInteger i = 0; i < self.qualityControl.numberOfSegments; i++) {
            NSString *quality = [self.qualityControl titleForSegmentAtIndex:i];
            BOOL available = [self.availableQualities containsObject:quality];
            [self.qualityControl setEnabled:available forSegmentAtIndex:i];
        }
    });
}

- (void)playerManager:(id)manager didSelectStream:(StreamInfo *)stream forQuality:(NSString *)quality {
    NSLog(@"[DemoViewController] 选择了流：%@ -> %@", quality, stream);
    [self updateStatus:[NSString stringWithFormat:@"已选择%@清晰度", quality]];
}

- (void)playerManager:(id)manager didLoadMediaPlaylist:(MediaPlaylist *)mediaPlaylist {
    NSLog(@"[DemoViewController] 媒体播放列表加载完成，包含%lu个片段", (unsigned long)mediaPlaylist.segments.count);
    [self updateStatus:@"正在准备播放..."];
}

- (void)playerManager:(id)manager cacheHitForURL:(NSString *)url {
    NSLog(@"[DemoViewController] 缓存命中：%@", url);
    [self updateCacheInfo];
}

- (void)playerManager:(id)manager cacheMissForURL:(NSString *)url {
    NSLog(@"[DemoViewController] 缓存未命中：%@", url);
    [self updateCacheInfo];
}

- (void)playerManager:(id)manager playerDidChangeState:(AVPlayerItemStatus)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        switch (status) {
            case AVPlayerItemStatusReadyToPlay:
                [self updateStatus:@"播放中"];
                [self setupPlayerLayer];
                break;
                
            case AVPlayerItemStatusFailed:
                [self updateStatus:@"播放失败"];
                break;
                
            case AVPlayerItemStatusUnknown:
                [self updateStatus:@"状态未知"];
                break;
        }
    });
}

- (void)playerManager:(id)manager didFailWithError:(NSError *)error {
    NSLog(@"[DemoViewController] 播放失败：%@", error.localizedDescription);
    [self updateStatus:[NSString stringWithFormat:@"错误：%@", error.localizedDescription]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"播放错误" 
                                                                   message:error.localizedDescription 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
