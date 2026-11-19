TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ControlXPrefs
ControlXPrefs_FILES = $(wildcard *.m)
ControlXPrefs_FRAMEWORKS = UIKit CoreGraphics
ControlXPrefs_PRIVATE_FRAMEWORKS = Preferences
ControlXPrefs_INSTALL_PATH = /Library/PreferenceBundles
ControlXPrefs_CFLAGS = -fobjc-arc

# 调试区（运行日志 / 动作自检 / 系统接口诊断）默认不编进设置页；./build.sh debug 时打开
ifeq ($(CX_DEBUG_UI),1)
ControlXPrefs_CFLAGS += -DCX_DEBUG_UI=1
endif

include $(THEOS_MAKE_PATH)/bundle.mk
