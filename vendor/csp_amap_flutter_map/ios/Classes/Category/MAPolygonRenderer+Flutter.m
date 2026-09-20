//
//  MAPolygonRenderer+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/12.
//

#import "MAPolygonRenderer+Flutter.h"
#import "AMapPolygon.h"

@implementation MAPolygonRenderer (Flutter)

/// 根据 AMapPolygon 模型更新原生多边形渲染器的属性
- (void)updateRenderWithPolygon:(AMapPolygon *)polygon {
    // 设置边框宽度
    self.lineWidth = polygon.strokeWidth;
    // 设置边框颜色
    self.strokeColor  = polygon.strokeColor;
    // 设置填充颜色
    self.fillColor = polygon.fillColor;
    // 设置线连接类型
    self.lineJoinType = polygon.joinType;
    // 设置可见性
    if (polygon.visible) {
        self.alpha = 1.0;
    } else {
        self.alpha = 0;
    }
}

@end
