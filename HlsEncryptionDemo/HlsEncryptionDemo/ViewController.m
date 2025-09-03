//
//  ViewController.m
//  HlsEncryptionDemo
//
//  Created by ChaiLu on 2019/10/28.
//  Copyright © 2019 ChaiLu. All rights reserved.
//

#import "ViewController.h"
#import "Loader/M3U8Loader.h"

@interface ViewController () <M3U8PlayerDelegate, M3U8DownloaderDelegate>
@property (weak, nonatomic) IBOutlet UIButton *palyButton;
@property (weak, nonatomic) IBOutlet UIButton *downloadButton;
@property (weak, nonatomic) IBOutlet UIButton *playDownloadButton;
@property (nonatomic, strong) M3U8Player *m3u8Player;
@property (nonatomic, strong) M3U8Downloader *m3u8Downloader;
@property (nonatomic, strong) NSString *downloadedPath;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 初始化M3U8播放器
    M3U8AuthConfig *authConfig = [M3U8AuthConfig defaultTestConfig];
    self.m3u8Player = [[M3U8Player alloc] initWithAuthConfig:authConfig];
    self.m3u8Player.delegate = self;
    
    // 初始化M3U8下载器
    self.m3u8Downloader = [M3U8Downloader sharedDownloader];
    self.m3u8Downloader.delegate = self;
    [self.m3u8Downloader configureWithAuthConfig:authConfig];
    
    NSLog(@"[ViewController] M3U8组件初始化完成，版本: %@", [M3U8Loader version]);
}

- (IBAction)playButtonAction:(id)sender {
    // 使用文档中提供的测试URL
    NSString *testURL = @"https://cdn-aws-test2.playlet.com/hls/v1/i18n/vip/1071/1/1_4434a0517b48f0b887656eba0ca0ed74_1451089_0.m3u8";
    
    // 开始播放（图层会在播放准备完毕后设置）
    [self.m3u8Player playM3U8WithURL:testURL];
    
    NSLog(@"[ViewController] 开始播放M3U8视频：%@", testURL);
}



- (IBAction)downloadButtonAction:(id)sender {
    NSString *testURL = @"https://cdn-aws-test2.playlet.com/hls/v1/vip/9032/1/1_8875c78f5cd0f238d6bd4d5d9c718ca9.m3u8";
    
    if (self.m3u8Downloader.isDownloading) {
        NSLog(@"[ViewController] 已有下载任务在进行中");
        return;
    }
    
    // 开始下载
    [self.m3u8Downloader downloadM3U8WithURL:testURL];
    
    NSLog(@"[ViewController] 开始下载M3U8视频");
}



- (IBAction)playDownloadButtonAction:(id)sender {
    if (self.downloadedPath) {
        NSString *homePath = NSHomeDirectory();
        NSString *filePath = [homePath stringByAppendingFormat:@"/%@", self.downloadedPath];
        
        // 播放本地文件（图层会在播放准备完毕后设置）
        [self.m3u8Player playLocalM3U8WithPath:filePath];
        
        NSLog(@"[ViewController] 开始播放本地M3U8视频: %@", filePath);
    } else {
        NSLog(@"[ViewController] 请先点击下载");
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                       message:@"请先下载视频" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    }
}


#pragma mark - M3U8PlayerDelegate

- (void)m3u8Player:(M3U8Player *)player statusDidChange:(AVPlayerStatus)status {
    switch (status) {
        case AVPlayerStatusUnknown:
            NSLog(@"[ViewController] 播放器状态：未知");
            break;
        case AVPlayerStatusReadyToPlay:
        {
            NSLog(@"[ViewController] 播放器状态：准备完毕，开始播放");
            // 在播放准备完毕时设置播放器图层
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.m3u8Player setupPlayerLayerInView:self.view];
                NSLog(@"[ViewController] 播放器图层设置完成，视图尺寸: %@", NSStringFromCGRect(self.view.bounds));
            });
        }
            break;
        case AVPlayerStatusFailed:
            NSLog(@"[ViewController] 播放器状态：播放失败");
            break;
    }
}

- (void)m3u8Player:(M3U8Player *)player didFailWithError:(NSError *)error {
    NSLog(@"[ViewController] 播放失败: %@", error.localizedDescription);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"播放错误" 
                                                                   message:error.localizedDescription 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)m3u8Player:(M3U8Player *)player willRequestKeyForURL:(NSString *)keyURL {
    NSLog(@"[ViewController] 即将请求密钥: %@", keyURL);
}

- (void)m3u8Player:(M3U8Player *)player didReceiveKeyData:(NSData *)keyData forURL:(NSString *)keyURL {
    NSLog(@"[ViewController] 密钥获取成功，长度: %lu", (unsigned long)keyData.length);
}

- (void)m3u8Player:(M3U8Player *)player didFailToLoadKeyForURL:(NSString *)keyURL error:(NSError *)error {
    NSLog(@"[ViewController] 密钥获取失败: %@", error.localizedDescription);
}

#pragma mark - M3U8DownloaderDelegate

- (void)m3u8Downloader:(id)downloader downloadProgress:(float)progress {
    NSLog(@"[ViewController] 下载进度: %.2f%%", progress * 100);
}

- (void)m3u8Downloader:(id)downloader didFinishDownloadingToPath:(NSString *)path {
    NSLog(@"[ViewController] 下载完成: %@", path);
    self.downloadedPath = path;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载完成" 
                                                                   message:@"视频下载完成，可以播放本地视频了" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)m3u8Downloader:(id)downloader didFailWithError:(NSError *)error {
    NSLog(@"[ViewController] 下载失败: %@", error.localizedDescription);
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载错误" 
                                                                   message:error.localizedDescription 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end
