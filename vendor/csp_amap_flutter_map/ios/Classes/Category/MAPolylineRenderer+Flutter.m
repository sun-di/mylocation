//
//  MAPolylineRenderer+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/7.
//

#import "MAPolylineRenderer+Flutter.h"
#import "AMapPolyline.h"

@implementation MAPolylineRenderer (Flutter)

/// 根据 AMapPolyline 模型更新原生折线渲染器的属性
- (void)updateRenderWithPolyline:(AMapPolyline *)polyline {
    // 设置线宽
    self.lineWidth = polyline.width;
    // 设置线颜色
    self.strokeColor  = polyline.color;
    // 设置可见性和透明度
    if (polyline.visible) {//可见时，才设置透明度
        self.alpha = polyline.alpha;
    } else {
        self.alpha = 0;
    }
    // 设置自定义纹理图片
    if (polyline.strokeImage) {
        self.strokeImage = polyline.strokeImage;
    }
    // 设置虚线类型
    self.lineDashType = polyline.dashLineType;
    // 设置线连接类型
    self.lineJoinType = polyline.joinType;
    // 设置线端点类型
    self.lineCapType = polyline.capType;
    // 默认可点击
    self.userInteractionEnabled = YES;
}

@end
