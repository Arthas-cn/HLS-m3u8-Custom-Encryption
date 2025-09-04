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
@property (nonatomic, strong) NSString *originalURL;
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
    // 从自定义scheme URL中提取原始URL
    NSString *assetURLString = asset.URL.absoluteString;
    if ([assetURLString hasPrefix:@"m3u8-custom://"]) {
        self.originalURL = [assetURLString stringByReplacingOccurrencesOfString:@"m3u8-custom://" withString:@"https://"];
        NSLog(@"[M3U8KeyManager] 设置原始URL: %@", self.originalURL);
    }
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
        NSLog(@"[M3U8KeyManager] 请求URL为空");
        return NO;
    }
    
    NSLog(@"[M3U8KeyManager] 拦截到请求: %@", url);
    
    // 处理自定义scheme的请求
    if ([url hasPrefix:@"m3u8-custom://"]) {
        // 将自定义scheme转换回真实URL
        NSString *realURL = [url stringByReplacingOccurrencesOfString:@"m3u8-custom://" withString:@"https://"];
        NSLog(@"[M3U8KeyManager] 转换为真实URL: %@", realURL);
        
        // 判断请求类型
        if ([realURL hasSuffix:@".m3u8"]) {
            // M3U8文件请求
            [self handleM3U8Request:loadingRequest withURL:realURL];
            return YES;
        } else if ([realURL hasSuffix:@".ts"]) {
            // TS文件请求
            [self handleTSRequest:loadingRequest withURL:realURL];
            return YES;
        }
    }
    
    // 拦截密钥请求
    if ([url hasPrefix:@"m3u8-key://"] ||
        [url containsString:@"api2-test.playletonline.com"] || 
        [url containsString:@"hlsVerify"] ||
        [url hasSuffix:@".key"]) {
        NSLog(@"[M3U8KeyManager] 检测到密钥请求，开始处理");
        // 如果是自定义scheme，转换为真实URL
        NSString *realKeyURL = url;
        if ([url hasPrefix:@"m3u8-key://"]) {
            realKeyURL = [url stringByReplacingOccurrencesOfString:@"m3u8-key://" withString:@"https://"];
        }
        [self handleKeyRequest:loadingRequest withURL:realKeyURL isLocal:self.isLocalMode];
        return YES;
    }
    
    NSLog(@"[M3U8KeyManager] 非密钥请求，不处理: %@", url);
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

#pragma mark - Request Handlers

- (void)handleM3U8Request:(AVAssetResourceLoadingRequest *)loadingRequest withURL:(NSString *)url {
    NSLog(@"[M3U8KeyManager] 处理M3U8请求: %@", url);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSData *data = [self downloadDataFromURL:url];
        
        if (data) {
            // 修改M3U8内容，将密钥URL替换为自定义scheme
            NSString *content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *modifiedContent = [content stringByReplacingOccurrencesOfString:@"https://" withString:@"m3u8-key://"];
            
            // 也需要将TS文件URL替换为自定义scheme
            modifiedContent = [self replaceRelativeURLsInM3U8:modifiedContent withBaseURL:url];
            
            NSData *modifiedData = [modifiedContent dataUsingEncoding:NSUTF8StringEncoding];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [[loadingRequest dataRequest] respondWithData:modifiedData];
                [loadingRequest finishLoading];
                NSLog(@"[M3U8KeyManager] M3U8请求处理完成");
            });
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self finishLoadingWithError:loadingRequest message:@"M3U8文件下载失败"];
            });
        }
    });
}

- (void)handleTSRequest:(AVAssetResourceLoadingRequest *)loadingRequest withURL:(NSString *)url {
    NSLog(@"[M3U8KeyManager] 处理TS请求: %@", url);
    
    // 直接重定向到真实URL
    NSURL *realURL = [NSURL URLWithString:url];
    NSURLRequest *redirect = [NSURLRequest requestWithURL:realURL];
    [loadingRequest setRedirect:redirect];
    [loadingRequest setResponse:[[NSHTTPURLResponse alloc] initWithURL:realURL statusCode:302 HTTPVersion:nil headerFields:nil]];
    [loadingRequest finishLoading];
}

- (NSString *)replaceRelativeURLsInM3U8:(NSString *)content withBaseURL:(NSString *)baseURL {
    NSURL *base = [NSURL URLWithString:baseURL];
    NSString *baseURLString = [NSString stringWithFormat:@"%@://%@", base.scheme, base.host];
    if (base.path.length > 0) {
        NSString *basePath = [base.path stringByDeletingLastPathComponent];
        baseURLString = [baseURLString stringByAppendingString:basePath];
    }
    
    // 替换相对路径的TS文件为自定义scheme
    NSArray *lines = [content componentsSeparatedByString:@"\n"];
    NSMutableArray *modifiedLines = [NSMutableArray array];
    
    for (NSString *line in lines) {
        if ([line hasSuffix:@".ts"] && ![line hasPrefix:@"http"]) {
            // 相对路径的TS文件
            NSString *fullTSURL = [baseURLString stringByAppendingFormat:@"/%@", line];
            NSString *customTSURL = [fullTSURL stringByReplacingOccurrencesOfString:@"https://" withString:@"m3u8-custom://"];
            [modifiedLines addObject:customTSURL];
        } else {
            [modifiedLines addObject:line];
        }
    }
    
    return [modifiedLines componentsJoinedByString:@"\n"];
}

- (NSData *)downloadDataFromURL:(NSString *)url {
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    __block NSData *result = nil;
    
    AFHTTPSessionManager *manager = [AFHTTPSessionManager manager];
    manager.responseSerializer = [AFHTTPResponseSerializer serializer];
    
    [manager GET:url parameters:nil headers:nil progress:nil success:^(NSURLSessionDataTask * _Nonnull task, id  _Nullable responseObject) {
        result = responseObject;
        NSLog(@"[M3U8KeyManager] 数据下载成功，长度: %lu", (unsigned long)result.length);
        dispatch_semaphore_signal(semaphore);
    } failure:^(NSURLSessionDataTask * _Nullable task, NSError * _Nonnull error) {
        NSLog(@"[M3U8KeyManager] 数据下载失败: %@", error.localizedDescription);
        result = nil;
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    return result;
}

- (void)finishLoadingWithError:(AVAssetResourceLoadingRequest *)loadingRequest message:(NSString *)message {
    NSError *error = [[NSError alloc] initWithDomain:NSURLErrorDomain 
                                                 code:400 
                                             userInfo:@{NSLocalizedDescriptionKey: message}];
    [loadingRequest finishLoadingWithError:error];
}

@end
