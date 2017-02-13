//
//  KFAppDelegate.m
//  KFDemo
//
//  Created by Christopher Ballinger on 1/28/14.
//  Copyright (c) 2014 Kickflip. All rights reserved.
//

#import "KFAppDelegate.h"
#import "KFDemoViewController.h"
#import "Kickflip.h"
#import "KFSecrets.h"
#import "KFLog.h"
#import "DDTTYLogger.h"
#import "KFOnboardingViewController.h"

@implementation KFAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    // Override point for customization after application launch.
    self.window.backgroundColor = [UIColor whiteColor];
    
    //[Kickflip setupWithAPIKey:KICKFLIP_API_KEY secret:KICKFLIP_API_SECRET]; //del by tzx
    [Kickflip setMaxBitrate:2000*1000]; // 2 Mbps
    
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    KFDemoViewController *demoVC = [[KFDemoViewController alloc] init];
    
    self.window.rootViewController = [[UINavigationController alloc] initWithRootViewController:demoVC];
    [self.window makeKeyAndVisible];
    //signal(SIGPIPE, SIG_IGN);
    return YES;
}

- (void)applicationWillResignActive:(UIApplication *)application
{
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application
{
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication *)application
{
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
}

@end
