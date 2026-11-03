//
//  QingPingStore.m
//

#import "QingPingStore.h"
#import "QingPingConfig.h"
#import <CoreFoundation/CoreFoundation.h>
#import <UIKit/UIKit.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>

static NSString * const kRootKey  = @"root";
static NSString * const kLockPath = @"/tmp/.qingping.stats.lock";
static const NSUInteger kRecentLimit = 120;

@implementation QPStore

static dispatch_queue_t QPStoreQueue(void) {
    static dispatch_queue_t q;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        q = dispatch_queue_create("com.qingping.store", DISPATCH_QUEUE_SERIAL);
    });
    return q;
}

static NSDateFormatter *QPDayFormatter(void) {
    static NSDateFormatter *f;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        f = [[NSDateFormatter alloc] init];
        f.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        f.dateFormat = @"yyyy-MM-dd";
        f.timeZone = [NSTimeZone localTimeZone];
    });
    return f;
}

static int QPLockAcquire(void) {
    int fd = open(kLockPath.fileSystemRepresentation, O_CREAT | O_RDWR, 0644);
    if (fd >= 0) {
        flock(fd, LOCK_EX);
    }
    return fd;
}

static void QPLockRelease(int fd) {
    if (fd >= 0) {
        flock(fd, LOCK_UN);
        close(fd);
    }
}

static NSMutableDictionary *QPRoot(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)QPStatsDomain);
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kRootKey,
                                                        (__bridge CFStringRef)QPStatsDomain);
    NSMutableDictionary *root = nil;
    if (value != NULL) {
        if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
            root = [(__bridge NSDictionary *)value mutableCopy];
        }
        CFRelease(value);
    }
    return root ?: [NSMutableDictionary dictionary];
}

static void QPWriteRoot(NSDictionary *root) {
    CFPreferencesSetAppValue((__bridge CFStringRef)kRootKey,
                             (__bridge CFDictionaryRef)root,
                             (__bridge CFStringRef)QPStatsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)QPStatsDomain);
}

/// 沙盒内的自有副本。
/// 被 TrollFools 注入进 App Store 应用时，「跨域写偏好」不一定被放行，
/// 但写自己容器的 Application Support 一定成功。清屏 App 用
/// platform-application 权限扫描各容器汇总（见 StatsStore.loadContainers）。
static NSString *QPContainerStatsPath(void) {
    static NSString *path = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray<NSString *> *dirs = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory,
                                                                       NSUserDomainMask, YES);
        NSString *base = dirs.firstObject;
        if (base.length == 0) return;
        NSString *dir = [base stringByAppendingPathComponent:@"QingPing"];
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
        path = [dir stringByAppendingPathComponent:@"stats.json"];
    });
    return path;
}

static void QPWriteContainerCopy(NSDictionary *root) {
    NSString *path = QPContainerStatsPath();
    if (path.length == 0) return;
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
    if (data == nil) return;
    [data writeToFile:path atomically:YES];
}

/// 具名剪贴板通道。
/// 沙盒挡得住文件，挡不住剪贴板服务；TrollStore 环境下这是唯一稳定的跨 App 通道。
/// 用具名 pasteboard，不会污染用户平时复制的文本。
static void QPWritePasteboard(NSDictionary *root) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:root options:0 error:NULL];
    if (data == nil) return;
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (text.length == 0) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        UIPasteboard *board = [UIPasteboard pasteboardWithName:@"com.qingping.stats" create:YES];
        if (board == nil) return;
        board.string = text;
    });
}

+ (void)recordEvent:(QPEventKind)kind
             bundle:(NSString *)bundleID
            appName:(NSString *)appName
             detail:(nullable NSString *)detail {
    if (bundleID.length == 0) return;

    NSString *kindString = (kind == QPEventKindSplash) ? @"splash" : @"misclick";
    NSString *name = appName.length > 0 ? appName : bundleID;
    NSString *note = detail.length > 0 ? detail : @"";

    dispatch_async(QPStoreQueue(), ^{
        NSDate *now = [NSDate date];
        NSTimeInterval ts = now.timeIntervalSince1970;
        NSString *day = [QPDayFormatter() stringFromDate:now];

        int fd = QPLockAcquire();

        @try {
            NSMutableDictionary *root = QPRoot();
            root[@"version"] = @1;
            root[@"updatedAt"] = @(ts);

            NSMutableDictionary *apps = [root[@"apps"] mutableCopy];
            if (apps == nil) apps = [NSMutableDictionary dictionary];

            NSMutableDictionary *app = [apps[bundleID] mutableCopy];
            if (app == nil) app = [NSMutableDictionary dictionary];
            app[@"name"] = name;
            app[@"last"] = @(ts);
            NSInteger splash = [app[@"splash"] integerValue];
            NSInteger misclick = [app[@"misclick"] integerValue];
            if (kind == QPEventKindSplash) {
                splash += 1;
            } else {
                misclick += 1;
            }
            app[@"splash"] = @(splash);
            app[@"misclick"] = @(misclick);
            apps[bundleID] = app;
            root[@"apps"] = apps;

            NSMutableDictionary *daily = [root[@"daily"] mutableCopy];
            if (daily == nil) daily = [NSMutableDictionary dictionary];
            daily[day] = @([daily[day] integerValue] + 1);
            root[@"daily"] = daily;

            NSMutableDictionary *totals = [root[@"totals"] mutableCopy];
            if (totals == nil) totals = [NSMutableDictionary dictionary];
            totals[@"splash"] = @([totals[@"splash"] integerValue] + (kind == QPEventKindSplash ? 1 : 0));
            totals[@"misclick"] = @([totals[@"misclick"] integerValue] + (kind == QPEventKindSplash ? 0 : 1));
            root[@"totals"] = totals;

            NSMutableArray *recent = [root[@"recent"] mutableCopy];
            if (recent == nil) recent = [NSMutableArray array];
            [recent insertObject:@{
                @"bid": bundleID,
                @"name": name,
                @"kind": kindString,
                @"detail": note,
                @"ts": @(ts),
            } atIndex:0];
            if (recent.count > kRecentLimit) {
                [recent removeObjectsInRange:NSMakeRange(kRecentLimit, recent.count - kRecentLimit)];
            }
            root[@"recent"] = recent;

            QPWriteRoot(root);
            QPWriteContainerCopy(root);
            QPWritePasteboard(root);
        } @catch (NSException *exception) {
            NSLog(@"[QingPing] store error: %@", exception);
        }

        QPLockRelease(fd);
    });
}

+ (void)markLoaded:(NSString *)bundleID appName:(NSString *)appName {
    if (bundleID.length == 0) return;
    NSString *name = appName.length > 0 ? appName : bundleID;

    dispatch_async(QPStoreQueue(), ^{
        NSTimeInterval ts = [[NSDate date] timeIntervalSince1970];
        int fd = QPLockAcquire();

        @try {
            NSMutableDictionary *root = QPRoot();
            root[@"version"] = @1;
            root[@"updatedAt"] = @(ts);

            NSMutableDictionary *apps = [root[@"apps"] mutableCopy];
            if (apps == nil) apps = [NSMutableDictionary dictionary];

            NSMutableDictionary *app = [apps[bundleID] mutableCopy];
            if (app == nil) app = [NSMutableDictionary dictionary];
            app[@"name"] = name;
            app[@"loadedAt"] = @(ts);
            apps[bundleID] = app;
            root[@"apps"] = apps;

            QPWriteRoot(root);
            QPWriteContainerCopy(root);
            QPWritePasteboard(root);
        } @catch (NSException *exception) {
            NSLog(@"[QingPing] markLoaded error: %@", exception);
        }

        QPLockRelease(fd);
    });
}

@end
