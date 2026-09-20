//
//  MAPolyline+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/9.
//

#import "MAPolyline+Flutter.h"
#import <objc/runtime.h>

@implementation MAPolyline (Flutter)

/// 获取 polylineId（通过关联对象实现）
- (NSString *)polylineId {
    return objc_getAssociatedObject(self, @selector(polylineId));
}

/// 设置 polylineId（通过关联对象实现）
- (void)setPolylineId:(NSString * _Nonnull)polylineId {
    objc_setAssociatedObject(self, @selector(polylineId), polylineId, OBJC_ASSOCIATION_COPY);
}

/// 通过 polylineId 初始化 MAPolyline
- (instancetype)initWithPolylineId:(NSString *)polylineId {
    self = [super init];
    if (self) {
        self.polylineId = polylineId;
    }
    return self;
}

@end
