# ControlX —— 默认打 roothide 包；打 rootless 包：./build.sh rootless
TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard
THEOS_PACKAGE_SCHEME ?= roothide

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ControlX
ControlX_FILES = Tweak/Tweak.x Tweak/CXActions.m Tweak/CXBlocks.m
ControlX_FRAMEWORKS = UIKit CoreGraphics
ControlX_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += prefs
include $(THEOS_MAKE_PATH)/aggregate.mk
