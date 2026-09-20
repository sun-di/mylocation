//
//  MAPointAnnotation+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/9.
//

#import "MAPointAnnotation+Flutter.h"
#import <objc/runtime.h>

// 标注视图的唯一标识符常量
NSString *const AMapFlutterAnnotationViewIdentifier = @"AMapFlutterAnnotationViewIdentifier";

@implementation MAPointAnnotation (Flutter)

/// 获取 markerId（通过关联对象实现）
- (NSString *)markerId {
    return objc_getAssociatedObject(self, @selector(markerId));
}

/// 设置 markerId（通过关联对象实现）
- (void)setMarkerId:(NSString * _Nonnull)markerId {
    objc_setAssociatedObject(self, @selector(markerId), markerId, OBJC_ASSOCIATION_COPY);
}

/// 通过 markerId 初始化 MAPointAnnotation
- (instancetype)initWithMarkerId:(NSString *)markerId {
    self = [super init];
    if (self) {
        self.markerId = markerId;
    }
    return self;
}

@end
