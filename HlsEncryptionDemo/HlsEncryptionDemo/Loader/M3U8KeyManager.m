//
//  M3U8KeyManager.m
//  HlsEncryptionDemo
//
//  Created by Assistant on 2024/12/19.
//  Copyright © 2024 ChaiLu. All rights reserved.
//

#import "M3U8KeyManager.h"
#import "AFNetworking.h"

@interface M3U8KeyManager ()
@property (nonatomic, strong) NSMutableDictionary *keyCache;
@property (nonatomic, assign) BOOL isLocalMode;
@end

@implementation M3U8KeyManager

+ (instancetype)sharedManager {
    static M3U8KeyManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[M3U8KeyManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _keyCache = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void)configureWithAuthConfig:(M3U8AuthConfig *)authConfig {
    self.authConfig = authConfig;
}

- (void)setupResourceLoaderForAsset:(AVURLAsset *)asset {
    self.isLocalMode = NO;
    [[asset resourceLoader] setDelegate:self queue:dispatch_get_main_queue()];
}

- (void)setupResourceLoaderForLocalAsset:(AVURLAsset *)asset {
    self.isLocalMode = YES;
    [[asset resourceLoader] setDelegate:self queue:dispatch_get_main_queue()];
}

#pragma mark - AVAssetResourceLoaderDelegate

- (BOOL)resourceLoader:(AVAssetResourceLoader *)resourceLoader shouldWaitForLoadingOfRequestedResource:(AVAssetResourceLoadingRequest *)loadingRequest {
    NSString *url = [[[loadingRequest request] URL] absoluteString];
    if (!url) {
        return NO;
    }
    
    NSLog(@"[M3U8KeyManager] 拦截到请求: %@", url);
    
    // 拦截密钥请求
    if ([url containsString:@"api2-test.playletonline.com/open/theater/hlsVerify"]) {
        [self handleKeyRequest:loadingRequest withURL:url isLocal:self.isLocalMode];
        return YES;
    }
    
    return NO;
}

#pragma mark - Private Methods

- (void)handleKeyRequest:(AVAssetResourceLoadingRequest *)loadingRequest withURL:(NSString *)url isLocal:(BOOL)isLocal {
    // 通知代理密钥请求开始
    if ([self.delegate respondsToSelector:@selector(m3u8Player:willRequestKeyForURL:)]) {
        [self.delegate m3u8Player:nil willRequestKeyForURL:url];
    }
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *keyData;
        
        if (isLocal) {
            // 本地播放，使用存储的密钥
            keyData = [self getStoredKeyDataForIdentifier:@"currentKey"];
            NSLog(@"[M3U8KeyManager] 使用本地存储的密钥");
        } else {
            // 网络播放，请求新密钥
            keyData = [self requestKeyDataForURL:url];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (keyData) {
                if (!isLocal) {
                    // 只有网络播放时才存储密钥
                    [self storeKeyData:keyData forIdentifier:@"currentKey"];
                }
                
                // 设置响应
                loadingRequest.contentInformationRequest.contentType = AVStreamingKeyDeliveryPersistentContentKeyType;
                [[loadingRequest dataRequest] respondWithData:keyData];
                [loadingRequest finishLoading];
                
                // 通知代理密钥获取成功
                if ([self.delegate respondsToSelector:@selector(m3u8Player:didReceiveKeyData:forURL:)]) {
                    [self.delegate m3u8Player:nil didReceiveKeyData:keyData forURL:url];
                }
            } else {
                NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain 
                                                            code:400 
                                                        userInfo:@{NSLocalizedDescriptionKey: isLocal ? @"本地密钥不存在" : @"密钥请求失败"}];
                [loadingRequest finishLoadingWithError:error];
                
                // 通知代理密钥获取失败
                if ([self.delegate respondsToSelector:@selector(m3u8Player:didFailToLoadKeyForURL:error:)]) {
                    [self.delegate m3u8Player:nil didFailToLoadKeyForURL:url error:error];
                }
            }
        });
    });
}

- (NSData *)requestKeyDataForURL:(NSString *)url {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *result = nil;
    
    // 获取授权配置
    M3U8AuthConfig *config = self.authConfig;
    
    // 如果代理实现了动态获取配置的方法，优先使用代理提供的配置
    if ([self.delegate respondsToSelector:@selector(m3u8Player:authConfigForKeyURL:)]) {
        M3U8AuthConfig *dynamicConfig = [self.delegate m3u8Player:nil authConfigForKeyURL:url];
        if (dynamicConfig) {
            config = dynamicConfig;
        }
    }
    
    if (!config) {
        NSLog(@"[M3U8KeyManager] 错误：未配置授权信息");
        dispatch_semaphore_signal(semaphore);
        return nil;
    }
    
    // 构建完整的请求URL
    NSString *authParams = [config authParamsString];
    NSString *fullURL;
    if ([url containsString:@"?"]) {
        fullURL = [NSString stringWithFormat:@"%@&%@", url, authParams];
    } else {
        fullURL = [NSString stringWithFormat:@"%@?%@", url, authParams];
    }
    
    NSLog(@"[M3U8KeyManager] 请求密钥地址: %@", fullURL);
    
    // 发送请求
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [manager GET:fullURL parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        result = responseObject;
        NSLog(@"[M3U8KeyManager] 密钥获取成功，长度: %lu", (unsigned long)result.length);
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"[M3U8KeyManager] 密钥请求失败: %@", error.localizedDescription);
        result = nil;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)storeKeyData:(NSData *)keyData forIdentifier:(NSString *)identifier {
    if (keyData && identifier) {
        [[NSUserDefaults standardUserDefaults] setObject:keyData forKey:identifier];
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog(@"[M3U8KeyManager] 密钥已存储，标识符: %@", identifier);
    }
}

- (NSData *)getStoredKeyDataForIdentifier:(NSString *)identifier {
    return [[NSUserDefaults standardUserDefaults] objectForKey:identifier];
}

@end
