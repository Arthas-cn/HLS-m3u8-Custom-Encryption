//
//  CLHlsResourcesLoader.m
//  HlsEncryptionDemo
//
//  Created by ChaiLu on 2019/10/28.
//  Copyright © 2019 ChaiLu. All rights reserved.
//

#import "CLHlsResourcesLoader.h"
#import "AFNetworking.h"

@interface CLHlsResourcesLoader ()
@end

@implementation CLHlsResourcesLoader
+ (CLHlsResourcesLoader *)shared {
    static CLHlsResourcesLoader *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone: nil] init];
    });
    return instance;
}

- (CLHlsResourcesLoader *)init {
    self = [super init];
    return self;
}

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString *url = [[[loadingRequest request] URL] absoluteString];
    if (!url) {
        return false;
    }
    
    NSLog(@"拦截到请求: %@", url);
    
    // 只拦截密钥请求，根据流程文档，密钥地址是：https://api2-test.playletonline.com/open/theater/hlsVerify
    if ([url containsString:@"api2-test.playletonline.com/open/theater/hlsVerify"]) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSData *data = [self KeyRequest:url];
            if (data) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    // 存储密钥供本地播放使用
                    [[NSUserDefaults standardUserDefaults] setObject:data forKey:@"localKey"];
                    loadingRequest.contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType;
                    [[loadingRequest dataRequest] respondWithData: data];
                    [loadingRequest finishLoading];
                });
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self finishLoadingError: loadingRequest];
                });
            }
        });
        return true;
    }
    
    return false;
}

- (void)finishLoadingError: (AVAssetResourceLoadingRequest *)loadingRequest {
    [loadingRequest finishLoadingWithError: [[NSError alloc] initWithDomain: NSURLErrorDomain code: 400 userInfo: nil]];
}


- (NSData *)KeyRequest: (NSString *)url {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *result = nil;
    
    // 添加授权参数
    NSString *authParams = @"auth_key=666&uid=test&session=test&sign=test&theater_id=9032&chapter_id=1";
    NSString *newUrl;
    if ([url containsString:@"?"]) {
        newUrl = [NSString stringWithFormat:@"%@&%@", url, authParams];
    } else {
        newUrl = [NSString stringWithFormat:@"%@?%@", url, authParams];
    }
    
    NSLog(@"请求密钥地址: %@", newUrl);
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [manager GET:newUrl parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        result = responseObject;
        NSLog(@"密钥获取成功，长度: %lu", (unsigned long)result.length);
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"密钥请求失败: %@", error.localizedDescription);
        result = nil;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return result;
}

- (AVPlayerItem *)playItemWith: (NSString *)url {
    AVURLAsset *urlAsset = [[AVURLAsset alloc] initWithURL: [NSURL URLWithString:url] options: nil];
    [[urlAsset resourceLoader] setDelegate: self queue: dispatch_get_main_queue()];
    AVPlayerItem *item = [[AVPlayerItem alloc] initWithAsset: urlAsset];
    [item setCanUseNetworkResourcesForLiveStreamingWhilePaused: YES];
    return item;
}

- (AVURLAsset *)downLoadAssetWith:(NSString *)url {
    AVURLAsset *urlAsset = [[AVURLAsset alloc] initWithURL: [NSURL URLWithString:url] options: nil];
    [[urlAsset resourceLoader] setDelegate: self queue: dispatch_get_main_queue()];
    return urlAsset;
}

@end
