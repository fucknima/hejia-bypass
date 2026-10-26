TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HeJiaBypass

# 六合一模块
#   Tweak.xm      扣检测（越狱/篡改/注入/调试/代理）
#   NoAds.xm      广告屏蔽（网络断流 + SDK 假生效）
#   UIPanel.mm    我的页右上角图标入口
#   SettingsVC.mm 设置页
#   TabHide.mm    隐藏「服务」「发现」
HeJiaBypass_FILES = Tweak.xm NoAds.xm UIPanel.mm SettingsVC.mm TabHide.mm

HeJiaBypass_CFLAGS = -fobjc-arc -O2 -Wno-deprecated-declarations
HeJiaBypass_FRAMEWORKS = Foundation UIKit CoreFoundation CFNetwork
HeJiaBypass_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
