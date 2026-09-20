//
//  AMapMethodCallDispatcher.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/16.
//

#import "AMapMethodCallDispatcher.h"

@interface AMapMethodCallDispatcher ()

// 用于线程安全的递归锁
@property (nonatomic, strong) NSRecursiveLock *dictLock;

// 存储方法名与处理回调的字典
@property (nonatomic, strong) NSMutableDictionary *callDict;

@end

@implementation AMapMethodCallDispatcher

// 初始化方法，创建锁和字典
- (instancetype)init {
    self = [super init];
    if (self) {
        self.dictLock = [[NSRecursiveLock alloc] init];
        self.callDict = [[NSMutableDictionary alloc] init];
    }
    return self;
}

// 处理 Flutter 侧发来的方法调用
- (void)onMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    [self.dictLock lock];
    FlutterMethodCallHandler handle = [self.callDict objectForKey:call.method];
    [self.dictLock unlock];
    if (handle) {
        // 如果有对应的处理回调，则执行
        handle(call,result);
    } else {
        // 没有找到对应回调，输出日志并返回 nil
        NSLog(@"call method:%@ handler is null",call.method);
        result(nil);
    }
}

// 添加方法名与回调处理
- (void)addMethodName:(NSString *)methodName withHandler:(FlutterMethodCallHandler)handler {
    NSAssert((methodName.length > 0 && handler != nil), @"添加methodCall回调处理参数异常");
    [self.dictLock lock];
    [self.callDict setObject:handler forKey:methodName];
    [self.dictLock unlock];
}

// 移除指定方法名的回调处理
- (void)removeHandlerWithMethodName:(NSString *)methodName {
    NSAssert(methodName.length > 0, @"移除methodCall时，参数异常");
    [self.dictLock lock];
    [self.callDict removeObjectForKey:methodName];
    [self.dictLock unlock];
}

// 清空所有回调处理
- (void)clearAllHandler {
    [self.dictLock lock];
    [self.callDict removeAllObjects];
    [self.dictLock unlock];
}

@end
