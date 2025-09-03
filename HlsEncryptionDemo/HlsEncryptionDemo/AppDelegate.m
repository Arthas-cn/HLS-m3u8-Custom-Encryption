//
//  AppDelegate.m
//  HlsEncryptionDemo
//
//  Created by ChaiLu on 2019/10/28.
//  Copyright © 2019 ChaiLu. All rights reserved.
//

#import "AppDelegate.h"
#import "DemoViewController.h"

@interface AppDelegate ()


@end

@implementation AppDelegate


- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Override point for customization after application launch.
    _window = [[UIWindow alloc] init];
    _window.backgroundColor = UIColor.blackColor;
    [_window makeKeyAndVisible];
    DemoViewController *scene = [[DemoViewController alloc] init];
    UINavigationController *navi = [[UINavigationController alloc] initWithRootViewController:scene];
    _window.rootViewController = navi;
    return YES;
}

@end
