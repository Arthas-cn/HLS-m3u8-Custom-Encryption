//
//  CLHlsResourcesLocalLoad.m
//  HlsEncryptionDemo
//
//  Created by ChaiLu on 2019/10/28.
//  Copyright © 2019 ChaiLu. All rights reserved.
//

#import "CLHlsResourcesLocalLoad.h"

@interface CLHlsResourcesLocalLoad ()
@property (nonatomic, strong) NSString * path;
@end


@implementation CLHlsResourcesLocalLoad
+ (CLHlsResourcesLocalLoad *)shared {
    static CLHlsResourcesLocalLoad *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[super allocWithZone: nil] init];
    });
    return instance;
}
- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString *url = [[[loadingRequest request] URL] absoluteString];
    NSLog(@"本地播放拦截到请求: %@", url);
    
    // 拦截密钥请求，使用本地存储的密钥
    if ([url containsString:@"api2-test.playletonline.com/open/theater/hlsVerify"]) {
        NSData *localKey = [[NSUserDefaults standardUserDefaults] objectForKey:@"localKey"];
        if (localKey) {
            loadingRequest.contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType;
            [[loadingRequest dataRequest] respondWithData:localKey];
            [loadingRequest finishLoading];
            NSLog(@"使用本地存储的密钥，长度: %lu", (unsigned long)localKey.length);
            return true;
        } else {
            NSLog(@"本地密钥不存在");
            [loadingRequest finishLoadingWithError: [[NSError alloc] initWithDomain: NSURLErrorDomain code: 404 userInfo: @{NSLocalizedDescriptionKey: @"本地密钥不存在"}]];
            return true;
        }
    }
    
    return false;
}
- (AVPlayerItem *)playItemWithLocalPath:(NSString *)path  {
    self.path = path;
    AVURLAsset *urlAsset = [[AVURLAsset alloc] initWithURL: [NSURL fileURLWithPath:path]  options: nil];
    [[urlAsset resourceLoader] setDelegate: self queue: dispatch_get_main_queue()];
    AVPlayerItem *item = [[AVPlayerItem alloc] initWithAsset: urlAsset];

    return item;
}

@end
