//
//  Tweak.m
//  清屏 · 注入端（自包含实现，不依赖 Substrate / ElleKit）
//
//  为什么不用 Logos：
//  TrollFools 往 App Store 应用里注入的是「裸动态库」，它不会一并注入
//  MSHookMessageEx 所在的 hook 运行时。用 Logos 编译出来的 dylib 一加载
//  就会因符号缺失失败，所以这里直接用 Objective-C runtime 做方法替换。
//  好处是同一个 dylib 既能被 TrollFools 注入，也能在越狱环境里当普通 tweak 用。
//
//  运行位置：被保护 App 的进程内。清后台不会失效，因为代码就在目标 App 里；
//  开机后目标 App 第一次启动就会重新加载本 dylib，不需要任何守护进程。
//

#import <UIKit/UIKit.h>
#import <StoreKit/StoreKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#import "QingPingConfig.h"
#import "QingPingStore.h"

#define QPLog(fmt, ...) NSLog(@"[QingPing] " fmt, ##__VA_ARGS__)

#pragma mark - 全局状态

static BOOL QPActive = NO;
static NSTimeInterval QPWindowStart = 0;
static NSTimeInterval QPBackgroundedAt = 0;
static NSTimeInterval QPLastRecordAt = 0;
static NSTimeInterval QPLastTouchAt = 0;
static NSTimeInterval QPLastJumpAt = 0;
static BOOL QPSplashVisible = NO;
static NSTimeInterval QPSplashSeenAt = 0;
static NSInteger QPVisitBudget = 0;
static NSString *QPBundleID = nil;
static char kQPHandledKey;

static NSTimeInterval QPUptime(void) {
    return [NSProcessInfo processInfo].systemUptime;
}

static BOOL QPIsOn(void) {
    if (!QPActive) return NO;
    if (![QPConfig enabled]) return NO;
    if (QPBundleID.length > 0 && ![QPConfig shouldProtectBundle:QPBundleID]) return NO;
    return YES;
}

static BOOL QPInWindow(void) {
    if (!QPIsOn() || QPWindowStart <= 0) return NO;
    return (QPUptime() - QPWindowStart) <= [QPConfig detectWindow];
}

/// 开屏广告「正在展示」的时间窗，用于放行/拦截点击与跳转
static BOOL QPAdContextActive(void) {
    if (!QPSplashVisible) return NO;
    return (QPUptime() - QPSplashSeenAt) <= 8.0;
}

/// 检测到开屏广告的瞬间就进入「广告上下文」，
/// 这样即使随后没能点掉广告，点击与跳转依然会被保护。
static void QPMarkAdContext(void) {
    QPSplashVisible = YES;
    QPSplashSeenAt = QPUptime();
}

#pragma mark - 识别工具

static NSArray<NSString *> *QPAdClassKeywords(void) {
    static NSArray<NSString *> *keys;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        keys = @[
            @"Splash", @"splash", @"OpenScreen", @"LaunchAd", @"AdSplash",
            @"SplashAd", @"BUAd", @"CSJ", @"GDT", @"KSAd", @"KSSplash",
            @"BaiduMobAd", @"Sigmob", @"MBridge", @"Pangle", @"Mintegral",
            @"MTG", @"TanX", @"TBAd", @"WindAd", @"AdView", @"AdWindow",
        ];
    });
    return keys;
}

static BOOL QPClassLooksLikeAd(NSString *cls) {
    if (cls.length == 0) return NO;
    for (NSString *key in QPAdClassKeywords()) {
        if ([cls containsString:key]) return YES;
    }
    return NO;
}

static BOOL QPTextLooksLikeSkip(NSString *text) {
    if (text.length == 0 || text.length > 16) return NO;
    NSString *trimmed = [text stringByTrimmingCharactersInSet:
                         [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) return NO;
    if ([trimmed containsString:@"跳过"]) return YES;
    if ([trimmed containsString:@"关闭广告"]) return YES;
    NSString *lower = trimmed.lowercaseString;
    if ([lower isEqualToString:@"skip"] || [lower containsString:@"skip ad"]) return YES;
    return NO;
}

static UIControl *QPFindSkipControl(UIView *root, NSInteger depth) {
    if (root == nil || depth > 10 || QPVisitBudget <= 0) return nil;
    QPVisitBudget -= 1;

    NSString *text = nil;
    if ([root isKindOfClass:[UIButton class]]) {
        text = [(UIButton *)root titleForState:UIControlStateNormal];
    } else if ([root isKindOfClass:[UILabel class]]) {
        text = [(UILabel *)root text];
    }
    if (QPTextLooksLikeSkip(text)) {
        if ([root isKindOfClass:[UIControl class]]) return (UIControl *)root;
        UIView *parent = root.superview;
        for (int i = 0; i < 3 && parent != nil; i++) {
            if ([parent isKindOfClass:[UIControl class]]) return (UIControl *)parent;
            parent = parent.superview;
        }
    }

    for (UIView *sub in root.subviews) {
        UIControl *found = QPFindSkipControl(sub, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static UIView *QPFindAdView(UIView *root, NSInteger depth) {
    if (root == nil || depth > 10 || QPVisitBudget <= 0) return nil;
    QPVisitBudget -= 1;

    if (QPClassLooksLikeAd(NSStringFromClass([root class]))) return root;

    for (UIView *sub in root.subviews) {
        UIView *found = QPFindAdView(sub, depth + 1);
        if (found != nil) return found;
    }
    return nil;
}

static BOOL QPViewCoversScreen(UIView *view, CGFloat ratio) {
    if (view == nil || view.window == nil) return NO;
    CGRect rect = [view convertRect:view.bounds toView:view.window];
    CGSize screen = view.window.bounds.size;
    if (rect.size.width < 1 || rect.size.height < 1) return NO;
    CGFloat area = rect.size.width * rect.size.height;
    CGFloat screenArea = screen.width * screen.height;
    if (screenArea <= 0) return NO;
    return area >= screenArea * ratio;
}

static UIWindow *QPKeyWindow(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) return window;
        }
    }
    return [UIApplication sharedApplication].keyWindow;
}

static BOOL QPIsOnScreen(UIViewController *vc) {
    if (vc == nil || vc.isBeingDismissed) return NO;
    UIView *view = vc.viewIfLoaded;
    return view != nil && view.window != nil;
}

#pragma mark - 统计记录

static void QPRecord(QPEventKind kind, NSString *detail) {
    NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
    if (bundleID.length == 0) bundleID = @"unknown";
    [QPStore recordEvent:kind
                  bundle:bundleID
                 appName:[QPConfig appDisplayNameForBundle:bundleID]
                  detail:detail];
}

static void QPMarkSplash(NSString *detail) {
    QPSplashVisible = YES;
    QPSplashSeenAt = QPUptime();

    NSTimeInterval now = QPUptime();
    if (QPLastRecordAt > 0 && (now - QPLastRecordAt) < 1.5) return;
    QPLastRecordAt = now;
    QPRecord(QPEventKindSplash, detail);
    QPLog(@"splash skipped (%@)", detail);
}

static void QPRecordBlockedTouch(UIView *view) {
    NSTimeInterval now = QPUptime();
    if (now - QPLastTouchAt < 1.2) return;
    QPLastTouchAt = now;
    QPRecord(QPEventKindMisclick, [NSString stringWithFormat:@"touch:%@",
                                   NSStringFromClass([view class])]);
    QPLog(@"blocked ad touch (%@)", NSStringFromClass([view class]));
}

static void QPRecordBlockedJump(NSString *detail) {
    NSTimeInterval now = QPUptime();
    if (now - QPLastJumpAt < 1.2) return;
    QPLastJumpAt = now;
    QPRecord(QPEventKindMisclick, detail);
    QPLog(@"blocked jump (%@)", detail);
}

#pragma mark - 跳转判定

static BOOL QPIsStoreURL(NSURL *url) {
    NSString *text = url.absoluteString.lowercaseString;
    if (text.length == 0) return NO;
    if ([text hasPrefix:@"itms-apps://"]) return YES;
    if ([text hasPrefix:@"itms://"]) return YES;
    if ([text containsString:@"apps.apple.com"]) return YES;
    return NO;
}

static BOOL QPShouldBlockURL(NSURL *url) {
    if (!QPIsOn() || url == nil) return NO;

    BOOL adContext = QPAdContextActive();

    if (QPIsStoreURL(url) && (adContext || QPInWindow())) return YES;
    if (!adContext) return NO;

    NSString *scheme = url.scheme.lowercaseString;
    if (scheme.length == 0) return NO;

    static NSSet<NSString *> *safeSchemes;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        safeSchemes = [NSSet setWithObjects:@"http", @"https", @"mailto", @"tel", @"sms", @"file", nil];
    });
    return ![safeSchemes containsObject:scheme];
}

#pragma mark - 跳过动作

static void QPCloseController(UIViewController *vc, NSString *tag) {
    if (vc == nil) return;
    UIWindow *key = QPKeyWindow();

    // 1. 模态呈现的开屏控制器
    if (vc.presentingViewController != nil && !vc.isBeingDismissed) {
        [vc dismissViewControllerAnimated:NO completion:nil];
        QPMarkSplash(tag);
        return;
    }

    // 2. 广告 SDK 自建的独立 UIWindow
    UIWindow *hostWindow = vc.viewIfLoaded.window;
    if (hostWindow != nil && key != nil && hostWindow != key &&
        vc.parentViewController == nil && vc.presentingViewController == nil) {
        hostWindow.hidden = YES;
        QPMarkSplash(tag);
        return;
    }

    // 3. 广告是主控制器上的覆盖视图：只移除广告视图
    QPVisitBudget = 1200;
    UIView *adView = QPFindAdView(vc.viewIfLoaded, 0);
    if (adView != nil && adView.superview != nil &&
        ![adView isKindOfClass:[UIWindow class]]) {
        [adView removeFromSuperview];
        QPMarkSplash(tag);
        return;
    }

    // 4. 子控制器
    if (vc.parentViewController != nil) {
        [vc willMoveToParentViewController:nil];
        [vc.view removeFromSuperview];
        [vc removeFromParentViewController];
        QPMarkSplash(tag);
        return;
    }

    // 5. 兜底：不是根控制器就移除它的视图
    if (key != nil && vc != key.rootViewController && vc.view.superview != nil) {
        [vc.view removeFromSuperview];
        QPMarkSplash(tag);
    }
}

static void QPScheduleSkip(UIViewController *vc, NSString *tag, NSInteger attempt) {
    if (!QPIsOn() || vc == nil) return;

    if (attempt == 0) {
        if (objc_getAssociatedObject(vc, &kQPHandledKey) != nil) return;
        objc_setAssociatedObject(vc, &kQPHandledKey, @YES,
                                 OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    NSTimeInterval delay = (attempt == 0) ? 0.35 : 0.9;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!QPIsOn()) return;
        if (!QPIsOnScreen(vc)) {
            QPSplashVisible = NO;
            return;
        }

        QPVisitBudget = 1200;
        UIControl *skip = QPFindSkipControl(vc.viewIfLoaded, 0);

        if (skip != nil && [QPConfig skipMode] == QPSkipModeTapButton) {
            [skip sendActionsForControlEvents:UIControlEventTouchUpInside];
            QPMarkSplash(tag);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.9 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                if (QPIsOn() && QPIsOnScreen(vc) && attempt < 3) {
                    QPScheduleSkip(vc, tag, attempt + 1);
                }
            });
            return;
        }

        if (attempt >= 2) {
            QPCloseController(vc, tag);
            return;
        }
        QPScheduleSkip(vc, tag, attempt + 1);
    });
}

static void QPHandleController(UIViewController *vc) {
    if (!QPIsOn() || !QPInWindow() || vc == nil) return;
    if (objc_getAssociatedObject(vc, &kQPHandledKey) != nil) return;

    NSString *cls = NSStringFromClass([vc class]);
    if (cls.length == 0) return;
    if ([cls hasPrefix:@"UI"] || [cls hasPrefix:@"_UI"] ||
        [cls hasPrefix:@"SwiftUI"] || [cls hasPrefix:@"AV"] ||
        [cls hasPrefix:@"SK"] || [cls hasPrefix:@"WF"]) {
        return;
    }

    UIView *root = vc.viewIfLoaded;
    if (root == nil || root.window == nil) return;
    if (!QPViewCoversScreen(root, 0.6)) return;   // 只处理全屏层级

    BOOL nameHit = QPClassLooksLikeAd(cls);

    QPVisitBudget = 1200;
    UIControl *skip = QPFindSkipControl(root, 0);
    QPVisitBudget = 1200;
    UIView *adView = QPFindAdView(root, 0);

    BOOL viewHit = (adView != nil) && (skip != nil) &&
                   QPViewCoversScreen(adView, 0.45);

    if (!nameHit && !viewHit) return;
    if (nameHit) QPMarkAdContext();
    QPScheduleSkip(vc, cls, 0);
}

#pragma mark - 通知

static void QPInstallObservers(void) {
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];

    [center addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        NSTimeInterval now = QPUptime();
        BOOL fromBackground = (QPBackgroundedAt > 0) && ((now - QPBackgroundedAt) > 2.0);
        if (QPWindowStart <= 0 || fromBackground) {
            QPWindowStart = now;
            QPSplashVisible = NO;
            QPLastRecordAt = 0;
        }
        QPBackgroundedAt = 0;
    }];

    [center addObserverForName:UIApplicationDidEnterBackgroundNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
        QPBackgroundedAt = QPUptime();
        QPWindowStart = 0;
        QPSplashVisible = NO;
    }];
}

#pragma mark - Runtime 方法替换

// 说明：不用 %hook / MSHookMessageEx，改用 method_setImplementation，
// 这样 dylib 不依赖任何 hook 运行时，TrollFools 注入后可直接加载。

static IMP QPOrigViewDidAppear = NULL;
static IMP QPOrigPresent = NULL;
static IMP QPOrigHitTest = NULL;
static IMP QPOrigDidAddSubview = NULL;
static IMP QPOrigOpenURL = NULL;
static IMP QPOrigOpenURLWithOptions = NULL;
static IMP QPOrigLoadProduct = NULL;

static void QPHookedViewDidAppear(UIViewController *self, SEL _cmd, BOOL animated) {
    ((void (*)(id, SEL, BOOL))QPOrigViewDidAppear)(self, _cmd, animated);
    if (!QPIsOn() || !QPInWindow()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        QPHandleController(self);
    });
}

static void QPHookedPresent(UIViewController *self, SEL _cmd,
                            UIViewController *vc, BOOL animated,
                            void (^completion)(void)) {
    if (QPIsOn() && QPAdContextActive()) {
        Class storeClass = NSClassFromString(@"SKStoreProductViewController");
        if (storeClass != Nil && [vc isKindOfClass:storeClass]) {
            QPRecordBlockedJump(@"SKStoreProductViewController");
            return;   // 拦截 App Store 落地页（误触最常见去向）
        }
    }

    ((void (*)(id, SEL, UIViewController *, BOOL, void (^)(void)))QPOrigPresent)(self, _cmd, vc, animated, completion);

    if (!QPIsOn() || !QPInWindow()) return;
    NSString *cls = NSStringFromClass([vc class]);
    if (!QPClassLooksLikeAd(cls)) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        QPScheduleSkip(vc, cls, 0);
    });
}

static UIView *QPHookedHitTest(UIView *self, SEL _cmd, CGPoint point, UIEvent *event) {
    UIView *hit = ((UIView *(*)(id, SEL, CGPoint, UIEvent *))QPOrigHitTest)(self, _cmd, point, event);

    if (hit == nil) return nil;
    if (!QPIsOn()) return hit;
    if (!QPAdContextActive()) return hit;
    if (![QPConfig touchGuardEnabled]) return hit;

    BOOL allow = NO;
    UIView *cursor = hit;
    for (int i = 0; i < 6 && cursor != nil; i++) {
        NSString *text = nil;
        if ([cursor isKindOfClass:[UIButton class]]) {
            text = [(UIButton *)cursor titleForState:UIControlStateNormal];
        } else if ([cursor isKindOfClass:[UILabel class]]) {
            text = [(UILabel *)cursor text];
        }
        if (QPTextLooksLikeSkip(text)) { allow = YES; break; }
        cursor = cursor.superview;
    }
    if (allow) return hit;

    BOOL insideAd = NO;
    cursor = hit;
    for (int i = 0; i < 12 && cursor != nil; i++) {
        if (QPClassLooksLikeAd(NSStringFromClass([cursor class]))) {
            insideAd = YES;
            break;
        }
        cursor = cursor.superview;
    }
    if (!insideAd) return hit;

    QPRecordBlockedTouch(hit);
    return nil;
}

static void QPHookedDidAddSubview(UIWindow *self, SEL _cmd, UIView *subview) {
    ((void (*)(id, SEL, UIView *))QPOrigDidAddSubview)(self, _cmd, subview);

    if (!QPIsOn() || !QPInWindow()) return;
    NSString *cls = NSStringFromClass([subview class]);
    if (!QPClassLooksLikeAd(cls)) return;
    if (!QPViewCoversScreen(subview, 0.45)) return;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!QPIsOn() || subview.window == nil) return;
        UIWindow *key = QPKeyWindow();
        UIWindow *host = subview.window;
        if (host != nil && key != nil && host != key) {
            host.hidden = YES;
        } else {
            [subview removeFromSuperview];
        }
        QPMarkSplash(cls);
    });
}

static BOOL QPHookedOpenURL(UIApplication *self, SEL _cmd, NSURL *url) {
    if (QPShouldBlockURL(url)) {
        QPRecordBlockedJump(url.absoluteString ?: @"openURL");
        return NO;
    }
    return ((BOOL (*)(id, SEL, NSURL *))QPOrigOpenURL)(self, _cmd, url);
}

static void QPHookedOpenURLWithOptions(UIApplication *self, SEL _cmd,
                                       NSURL *url, NSDictionary *options,
                                       void (^completion)(BOOL)) {
    if (QPShouldBlockURL(url)) {
        QPRecordBlockedJump(url.absoluteString ?: @"openURL");
        if (completion) completion(NO);
        return;
    }
    ((void (*)(id, SEL, NSURL *, NSDictionary *, void (^)(BOOL)))QPOrigOpenURLWithOptions)(self, _cmd, url, options, completion);
}

static void QPHookedLoadProduct(SKStoreProductViewController *self, SEL _cmd,
                                NSDictionary *parameters,
                                void (^block)(BOOL, NSError *)) {
    if (QPIsOn() && (QPAdContextActive() || QPInWindow())) {
        QPRecordBlockedJump(@"SKStoreProductViewController");
        if (block) {
            block(NO, [NSError errorWithDomain:@"com.qingping"
                                          code:-1
                                      userInfo:@{NSLocalizedDescriptionKey: @"已由清屏拦截"}]);
        }
        return;
    }
    ((void (*)(id, SEL, NSDictionary *, void (^)(BOOL, NSError *)))QPOrigLoadProduct)(self, _cmd, parameters, block);
}

#pragma mark - 安装与启动

static BOOL QPClassImplementsSelector(Class cls, SEL sel) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    BOOL found = NO;
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(methods[i]) == sel) { found = YES; break; }
    }
    if (methods) free(methods);
    return found;
}

/// 替换类自身实现；若类没有自己的实现（只是继承），就补一个覆盖方法，
/// 原始实现取父类的。避免误改父类（例如把 UIView 的实现改到 UIWindow 上）。
static void QPReplaceMethod(Class cls, SEL sel, IMP newImp, IMP *outOriginal) {
    Method existing = class_getInstanceMethod(cls, sel);
    if (existing == NULL) {
        QPLog(@"method not found: %@ %@", cls, NSStringFromSelector(sel));
        return;
    }

    if (!QPClassImplementsSelector(cls, sel)) {
        const char *types = method_getTypeEncoding(existing);
        Class superClass = class_getSuperclass(cls);
        IMP superImp = superClass ? class_getMethodImplementation(superClass, sel) : NULL;
        if (types != NULL && class_addMethod(cls, sel, newImp, types)) {
            *outOriginal = superImp;
            return;
        }
    }

    if (outOriginal != NULL) {
        *outOriginal = method_getImplementation(existing);
    }
    method_setImplementation(existing, newImp);
}

static void QPInstallHooks(void) {
    Class vcClass = [UIViewController class];
    QPReplaceMethod(vcClass, @selector(viewDidAppear:), (IMP)QPHookedViewDidAppear, &QPOrigViewDidAppear);
    QPReplaceMethod(vcClass, @selector(presentViewController:animated:completion:), (IMP)QPHookedPresent, &QPOrigPresent);

    QPReplaceMethod([UIView class], @selector(hitTest:withEvent:), (IMP)QPHookedHitTest, &QPOrigHitTest);
    QPReplaceMethod([UIWindow class], @selector(didAddSubview:), (IMP)QPHookedDidAddSubview, &QPOrigDidAddSubview);

    QPReplaceMethod([UIApplication class], @selector(openURL:), (IMP)QPHookedOpenURL, &QPOrigOpenURL);
    QPReplaceMethod([UIApplication class], @selector(openURL:options:completionHandler:), (IMP)QPHookedOpenURLWithOptions, &QPOrigOpenURLWithOptions);

    Class storeClass = NSClassFromString(@"SKStoreProductViewController");
    if (storeClass != Nil) {
        QPReplaceMethod(storeClass, @selector(loadProductWithParameters:completionBlock:), (IMP)QPHookedLoadProduct, &QPOrigLoadProduct);
    }
}

__attribute__((constructor))
static void QPStart(void) {
    @autoreleasepool {
        NSString *bundleID = [NSBundle mainBundle].bundleIdentifier;
        QPLog(@"loaded into %@ (%@)", bundleID, [NSProcessInfo processInfo].processName);

        if (bundleID.length == 0) return;                        // 系统守护进程
        if (![QPConfig shouldProtectBundle:bundleID]) return;    // 系统 App / 忽略名单
        if (![QPConfig enabled]) return;                         // 总开关

        QPBundleID = [bundleID copy];
        QPActive = YES;
        QPWindowStart = QPUptime();

        QPInstallHooks();
        QPInstallObservers();

        QPLog(@"active for %@", bundleID);
    }
}
