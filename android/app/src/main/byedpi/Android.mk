LOCAL_PATH := $(call my-dir)
include $(CLEAR_VARS)
LOCAL_MODULE := byedpi
LOCAL_SRC_FILES := entry.c upstream/packets.c upstream/conev.c upstream/proxy.c upstream/desync.c upstream/mpool.c upstream/extend.c
LOCAL_CFLAGS := -std=c99 -D_DEFAULT_SOURCE -O2
LOCAL_LDFLAGS := -Wl,-z,max-page-size=16384
LOCAL_LDLIBS := -landroid
include $(BUILD_EXECUTABLE)
