//
//  FlutterMethodChannel+MethodCallDispatch.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/16.
//

#import "FlutterMethodChannel+MethodCallDispatch.h"
#import <objc/runtime.h>

@implementation FlutterMethodChannel (MethodCallDispatch)

/// 获取当前 channel 关联的方法分发器
- (AMapMethodCallDispatcher *)methodCallDispatcher {
    return objc_getAssociatedObject(self, @selector(methodCallDispatcher));
}

/// 设置当前 channel 的方法分发器
- (void)setMethodCallDispatcher:(AMapMethodCallDispatcher *)dispatcher {
    objc_setAssociatedObject(self, @selector(methodCallDispatcher), dispatcher, OBJC_ASSOCIATION_RETAIN);
}

/// 为 channel 添加方法名与回调处理，并自动初始化分发器和设置统一的 methodCallHandler
- (void)addMethodName:(NSString *)methodName withHandler:(FlutterMethodCallHandler)handler {
    if (self.methodCallDispatcher == nil) {
        // 首次添加时，初始化分发器并设置 methodCallHandler
        self.methodCallDispatcher = [[AMapMethodCallDispatcher alloc] init];
        __weak typeof(self) weakSelf = self;
        [self setMethodCallHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            if (weakSelf.methodCallDispatcher) {
                [weakSelf.methodCallDispatcher onMethodCall:call result:result];
            }
        }];
    }
    // 添加方法名与回调
    [self.methodCallDispatcher addMethodName:methodName withHandler:handler];
}

/// 移除指定方法名的回调处理
- (void)removeHandlerWithMethodName:(NSString *)methodName {
    [self.methodCallDispatcher removeHandlerWithMethodName:methodName];
}

/// 清空所有回调处理
- (void)clearAllHandler {
    [self.methodCallDispatcher clearAllHandler];
}

@end
