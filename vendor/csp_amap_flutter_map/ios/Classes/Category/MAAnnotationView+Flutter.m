//
//  MAAnnotationView+Flutter.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/5.
//

#import "MAAnnotationView+Flutter.h"
#import "AMapMarker.h"
#import "AMapInfoWindow.h"

@implementation MAAnnotationView (Flutter)

/// 根据 AMapMarker 模型更新原生标注视图的属性
- (void)updateViewWithMarker:(AMapMarker *)marker {
    if (marker == nil) {
        return;
    }
    // 设置透明度
    self.alpha = marker.alpha;
    // 设置图片
    self.image = marker.image;
    // anchor 转换为地图的 centerOffset
    if (self.image) {
        CGSize imageSize = self.image.size;
        // iOS 的 annotationView 的中心默认位于 annotation 的坐标位置, 对应锚点为（0.5，0.5）
        CGFloat offsetW = imageSize.width * (0.5 - marker.anchor.x);
        CGFloat offsetH = imageSize.height * (0.5 - marker.anchor.y);
        self.centerOffset = CGPointMake(offsetW, offsetH);
    }
    // 是否可点击
    self.enabled = marker.clickable;
    // 是否可拖拽
    self.draggable = marker.draggable;
    //    marker.flat;//flat属性，iOS暂时不开
    // 是否显示气泡
    self.canShowCallout = marker.infoWindowEnable;
    // TODO: 气泡的锚点，由于 iOS 中的气泡区分默认气泡和自定义气泡，且无法获得气泡的大小，所以没法将其锚点转换为 calloutOffset
    //    self.calloutOffset = marker.infoWindow.anchor;
    // 角度旋转
    self.imageView.transform = CGAffineTransformMakeRotation(marker.rotation / 180.f * M_PI);
    // 是否可见
    self.hidden = (!marker.visible);
    // 设置 zIndex
    self.zIndex = marker.zIndex;
}

@end
