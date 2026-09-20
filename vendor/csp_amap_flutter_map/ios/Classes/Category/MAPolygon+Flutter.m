//
//  MAPolygon+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/12.
//

#import "MAPolygon+Flutter.h"
#import <objc/runtime.h>

@implementation MAPolygon (Flutter)

/// 获取 polygonId（通过关联对象实现）
- (NSString *)polygonId {
    return objc_getAssociatedObject(self, @selector(polygonId));
}

/// 设置 polygonId（通过关联对象实现）
- (void)setPolygonId:(NSString * _Nonnull)polygonId {
    objc_setAssociatedObject(self, @selector(polygonId), polygonId, OBJC_ASSOCIATION_COPY);
}

/// 通过 polygonId 初始化 MAPolygon
- (instancetype)initWithPolygonId:(NSString *)polygonId {
    self = [super init];
    if (self) {
        self.polygonId = polygonId;
    }
    return self;
}

@end
