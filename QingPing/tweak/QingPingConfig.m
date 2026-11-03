//
//  QingPingConfig.m
//

#import "QingPingConfig.h"
#import <CoreFoundation/CoreFoundation.h>

NSString * const QPPrefsDomain = @"com.qingping.prefs";
NSString * const QPStatsDomain = @"com.qingping.stats";

static NSString * const kKeyEnabled    = @"enabled";
static NSString * const kKeySkipMode   = @"skipMode";
static NSString * const kKeyTouchGuard = @"touchGuard";
static NSString * const kKeyIgnoreList = @"ignoreList";
static NSString * const kKeyWindow     = @"detectWindow";
static NSString * const kRootKey       = @"root";

@interface QPConfig ()
+ (NSDictionary *)cachedPrefs;
+ (nullable id)prefValue:(NSString *)key;
@end

@implementation QPConfig

static NSDictionary *_cache = nil;
static NSTimeInterval _cacheAt = 0;

+ (void)reload {
    _cache = nil;
    _cacheAt = 0;
}

+ (NSDictionary *)cachedPrefs {
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if (_cache == nil || (now - _cacheAt) > 5.0) {
        CFPreferencesAppSynchronize((__bridge CFStringRef)QPPrefsDomain);
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)kRootKey,
                                                            (__bridge CFStringRef)QPPrefsDomain);
        NSDictionary *dict = nil;
        if (value != NULL) {
            if (CFGetTypeID(value) == CFDictionaryGetTypeID()) {
                dict = [(__bridge NSDictionary *)value copy];
            }
            CFRelease(value);
        }
        _cache = dict ?: @{};
        _cacheAt = now;
    }
    return _cache;
}

+ (nullable id)prefValue:(NSString *)key {
    return [self cachedPrefs][key];
}

+ (BOOL)enabled {
    id v = [self prefValue:kKeyEnabled];
    return v == nil ? YES : [v boolValue];
}

+ (QPSkipMode)skipMode {
    id v = [self prefValue:kKeySkipMode];
    if (v == nil) return QPSkipModeTapButton;
    NSInteger mode = [v integerValue];
    if (mode != QPSkipModeTapButton && mode != QPSkipModeForceClose) {
        return QPSkipModeTapButton;
    }
    return (QPSkipMode)mode;
}

+ (BOOL)touchGuardEnabled {
    id v = [self prefValue:kKeyTouchGuard];
    return v == nil ? YES : [v boolValue];
}

+ (BOOL)cleanWidgets {
    id v = [self prefValue:@"cleanWidgets"];
    return v == nil ? NO : [v boolValue];
}

+ (BOOL)cleanFeed {
    id v = [self prefValue:@"cleanFeed"];
    return v == nil ? NO : [v boolValue];
}

+ (NSTimeInterval)detectWindow {
    id v = [self prefValue:kKeyWindow];
    NSTimeInterval t = (v == nil) ? 15.0 : [v doubleValue];
    if (t < 5.0) t = 5.0;
    if (t > 60.0) t = 60.0;
    return t;
}

+ (BOOL)shouldProtectBundle:(NSString *)bundleID {
    if (bundleID.length == 0) return NO;
    if ([bundleID isEqualToString:@"com.qingping.app"]) return NO;
    if ([bundleID hasPrefix:@"com.qingping."]) return NO;
    if ([bundleID hasPrefix:@"com.apple."]) return NO;

    id list = [self prefValue:kKeyIgnoreList];
    if ([list isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)list) {
            if ([item isKindOfClass:[NSString class]] &&
                [(NSString *)item isEqualToString:bundleID]) {
                return NO;
            }
        }
    }
    return YES;
}

+ (NSString *)appDisplayNameForBundle:(NSString *)bundleID {
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *name = [bundle objectForInfoDictionaryKey:@"CFBundleDisplayName"];
    if (name.length == 0) name = [bundle objectForInfoDictionaryKey:@"CFBundleName"];
    if (name.length == 0) name = bundleID;
    return name ?: bundleID;
}

@end
