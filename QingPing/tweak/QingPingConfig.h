//
//  QingPingConfig.h
//  清屏 · 注入端配置读取
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 跳过方式
typedef NS_ENUM(NSInteger, QPSkipMode) {
    QPSkipModeTapButton  = 0, // 模拟点击广告上的「跳过」
    QPSkipModeForceClose = 1, // 直接移除广告视图 / 关闭广告控制器
};

/// 与「清屏」App 共享的偏好域（cfprefsd 中介，写入 /var/mobile/Library/Preferences/）
FOUNDATION_EXPORT NSString * const QPPrefsDomain;  // com.qingping.prefs
FOUNDATION_EXPORT NSString * const QPStatsDomain;  // com.qingping.stats

@interface QPConfig : NSObject

/// 清空缓存，下一次读取重新走 cfprefsd
+ (void)reload;

/// 总开关，默认 YES
+ (BOOL)enabled;

/// 跳过方式，默认 QPSkipModeTapButton
+ (QPSkipMode)skipMode;

/// 防误触：屏蔽广告区域内的点击，默认 YES
+ (BOOL)touchGuardEnabled;

/// 清理悬浮广告挂件（会移除窗口上的小浮层），默认 NO
+ (BOOL)cleanWidgets;

/// 清理信息流广告（自动点「×」或隐藏卡片内容），默认 NO
+ (BOOL)cleanFeed;

/// 开屏广告判定时间窗（秒），默认 15
+ (NSTimeInterval)detectWindow;

/// 是否对该 App 生效（系统 App、清屏自身、忽略名单一律不生效）
+ (BOOL)shouldProtectBundle:(NSString *)bundleID;

/// 读取宿主 App 的显示名
+ (NSString *)appDisplayNameForBundle:(NSString *)bundleID;

@end

NS_ASSUME_NONNULL_END
