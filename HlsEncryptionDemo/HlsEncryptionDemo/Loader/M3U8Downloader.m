//
//  M3U8Downloader.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8Downloader.h"
#import "M3U8KeyManager.h"

@interface M3U8Downloader () <AVAssetDownloadDelegate>
@property (nonatomic, strong) AVAssetDownloadURLSession *downloadSession;
@property (nonatomic, strong) AVAssetDownloadTask *downloadTask;
@property (nonatomic, strong) M3U8KeyManager *keyManager;
@property (nonatomic, assign) BOOL isDownloading;
@end

@implementation M3U8Downloader

+ (instancetype)sharedDownloader {
    static M3U8Downloader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[M3U8Downloader alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 创建后台下载会话
        NSURLSessionConfiguration *config = [NSURLSessionConfiguration backgroundSessionConfigurationWithIdentifier:@"M3U8Downloader"];
        _downloadSession = [AVAssetDownloadURLSession sessionWithConfiguration:config 
                                                        assetDownloadDelegate:self 
                                                                delegateQueue:[NSOperationQueue mainQueue]];
        
        _keyManager = [M3U8KeyManager sharedManager];
        _isDownloading = NO;
    }
    return self;
}

- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self.authConfig = authConfig;
    [self.keyManager configureWithAuthConfig:authConfig];
}

- (void)downloadM3U8WithURL:(NSString *)url {
    if (self.isDownloading) {
        NSLog(@"[M3U8Downloader] 已有下载任务在进行中");
        return;
    }
    
    NSLog(@"[M3U8Downloader] 开始下载: %@", url);
    
    // 创建Asset并设置资源加载器
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:[NSURL URLWithString:url] options:nil];
    [self.keyManager setupResourceLoaderForAsset:asset];
    
    // 创建下载任务
    self.downloadTask = [self.downloadSession assetDownloadTaskWithURLAsset:asset 
                                                                  assetTitle:@"M3U8Video" 
                                                            assetArtworkData:nil 
                                                                     options:nil];
    
    self.isDownloading = YES;
    [self.downloadTask resume];
}

- (void)cancelDownload {
    if (self.downloadTask) {
        [self.downloadTask cancel];
        self.downloadTask = nil;
        self.isDownloading = NO;
        NSLog(@"[M3U8Downloader] 下载已取消");
    }
}

- (float)downloadProgress {
    // 这个方法在AVAssetDownloadDelegate中会通过回调更新
    return 0.0f;
}

#pragma mark - AVAssetDownloadDelegate

- (void)URLSession:(NSURLSession *)session 
      assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask 
       didLoadTimeRange:(CMTimeRange)timeRange 
 totalTimeRangesLoaded:(NSArray<NSValue *> *)loadedTimeRanges 
timeRangeExpectedToLoad:(CMTimeRange)timeRangeExpectedToLoad {
    
    float percentComplete = 0.0f;
    for (NSValue *value in loadedTimeRanges) {
        CMTimeRange range = [value CMTimeRangeValue];
        percentComplete += range.duration.value * 1.0 / timeRangeExpectedToLoad.duration.value;
    }
    
    NSLog(@"[M3U8Downloader] 下载进度: %.2f%%", percentComplete * 100);
    
    // 通知代理下载进度
    if ([self.delegate respondsToSelector:@selector(m3u8Downloader:downloadProgress:)]) {
        [self.delegate m3u8Downloader:self downloadProgress:percentComplete];
    }
}

- (void)URLSession:(NSURLSession *)session 
      assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask 
didFinishDownloadingToURL:(NSURL *)location {
    
    self.isDownloading = NO;
    NSLog(@"[M3U8Downloader] 下载完成: %@", location.path);
    
    // 通知代理下载完成
    if ([self.delegate respondsToSelector:@selector(m3u8Downloader:didFinishDownloadingToPath:)]) {
        [self.delegate m3u8Downloader:self didFinishDownloadingToPath:location.relativePath];
    }
}

- (void)URLSession:(NSURLSession *)session 
      assetDownloadTask:(AVAssetDownloadTask *)assetDownloadTask 
didResolveMediaSelection:(AVMediaSelection *)resolvedMediaSelection {
    // 媒体选择解析完成
    NSLog(@"[M3U8Downloader] 媒体选择已解析");
}

- (void)URLSession:(NSURLSession *)session 
              task:(NSURLSessionTask *)task 
didCompleteWithError:(NSError *)error {
    
    self.isDownloading = NO;
    
    if (error) {
        NSLog(@"[M3U8Downloader] 下载失败: %@", error.localizedDescription);
        
        // 通知代理下载失败
        if ([self.delegate respondsToSelector:@selector(m3u8Downloader:didFailWithError:)]) {
            [self.delegate m3u8Downloader:self didFailWithError:error];
        }
    }
}

@end
