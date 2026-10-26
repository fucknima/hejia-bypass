TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HeJiaBypass
HeJiaBypass_FILES = Tweak.xm

# -fobjc-arc：启用 ARC
# -O2 与告警：与本地 verify/ci_simulate.sh 保持一致，保证两边行为相同
HeJiaBypass_CFLAGS = -fobjc-arc -O2 -Wno-deprecated-declarations

# CFNetworkCopySystemProxySettings 属于 CFNetwork，必须显式链接
# UIKit 用于 RunLoop/主队列相关调用
HeJiaBypass_FRAMEWORKS = Foundation UIKit CoreFoundation CFNetwork
HeJiaBypass_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
