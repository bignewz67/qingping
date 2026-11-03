//
//  QingPingStore.h
//  清屏 · 统计存储（跨进程）
//
//  设计说明：
//  注入端运行在「被保护 App」的进程里，无法访问清屏 App 的沙盒容器，
//  因此统计统一写入 cfprefsd 中介的 com.qingping.stats 域，
//  对应文件 /var/mobile/Library/Preferences/com.qingping.stats.plist。
//  清屏 App 用同一个 suite 读取即可，无需任何越狱专属 IPC。
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, QPEventKind) {
    QPEventKindSplash   = 0, // 开屏广告被跳过
    QPEventKindMisclick = 1, // 误触跳转被拦截
};

@interface QPStore : NSObject

/// 记录一次拦截事件（异步，不阻塞主线程）
+ (void)recordEvent:(QPEventKind)kind
             bundle:(NSString *)bundleID
            appName:(NSString *)appName
             detail:(nullable NSString *)detail;

@end

NS_ASSUME_NONNULL_END
