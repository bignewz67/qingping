export TARGET = iphone:clang:latest:16.0
export ARCHS = arm64 arm64e
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = QingPing

# 纯 Objective-C runtime 实现，不依赖 Logos / Substrate 符号：
#   - 越狱：当普通 tweak 装（由 Substrate/ElleKit 负责加载）
#   - 不越狱：把 QingPing.dylib 用 TrollFools 注入目标 App
QingPing_FILES = Tweak.m QingPingStore.m QingPingConfig.m
QingPing_CFLAGS = -fobjc-arc -Wall
QingPing_FRAMEWORKS = UIKit Foundation StoreKit

include $(THEOS_MAKE_PATH)/tweak.mk
