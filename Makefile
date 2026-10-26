TARGET := iphone:clang:latest:14.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HeJiaBypass
HeJiaBypass_FILES = Tweak.xm
HeJiaBypass_CFLAGS = -fobjc-arc -Wno-unused-function -Wno-deprecated-declarations
HeJiaBypass_FRAMEWORKS = Foundation UIKit CoreFoundation
HeJiaBypass_PRIVATE_FRAMEWORKS =
HeJiaBypass_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
