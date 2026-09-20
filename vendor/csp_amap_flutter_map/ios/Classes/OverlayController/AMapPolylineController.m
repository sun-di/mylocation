//
//  AMapPolylineController.m
//  amap_flutter_map
//
//  Created by lly on 2020/11/6.
//

#import "AMapPolylineController.h"
#import "AMapPolyline.h"
#import "AMapJsonUtils.h"
#import "AMapMarker.h"
#import "MAPolyline+Flutter.h"
#import "MAPolylineRenderer+Flutter.h"
#import "AMapConvertUtil.h"
#import "FlutterMethodChannel+MethodCallDispatch.h"

@interface AMapPolylineController ()

// 存储所有 polyline 的字典，key 为 polylineId
@property (nonatomic,strong) NSMutableDictionary<NSString*,AMapPolyline*> *polylineDict;
// Flutter 方法通道
@property (nonatomic,strong) FlutterMethodChannel *methodChannel;
// Flutter 插件注册器
@property (nonatomic,strong) NSObject<FlutterPluginRegistrar> *registrar;
// 地图视图
@property (nonatomic,strong) MAMapView *mapView;

@end

@implementation AMapPolylineController

// 构造方法，初始化通道、地图和注册器，并注册 Flutter 侧 polyline 更新的回调
- (instancetype)init:(FlutterMethodChannel*)methodChannel
             mapView:(MAMapView*)mapView
           registrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    self = [super init];
    if (self) {
        _methodChannel = methodChannel;
        _mapView = mapView;
        _polylineDict = [NSMutableDictionary dictionaryWithCapacity:1];
        _registrar = registrar;
        
        __weak typeof(self) weakSelf = self;
        // 注册 Flutter 侧 polylines#update 方法的回调
        [_methodChannel addMethodName:@"polylines#update" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
            id polylinesToAdd = call.arguments[@"polylinesToAdd"];
            if ([polylinesToAdd isKindOfClass:[NSArray class]]) {
                [weakSelf addPolylines:polylinesToAdd];
            }
            id polylinesToChange = call.arguments[@"polylinesToChange"];
            if ([polylinesToChange isKindOfClass:[NSArray class]]) {
                [weakSelf changePolylines:polylinesToChange];
            }
            id polylineIdsToRemove = call.arguments[@"polylineIdsToRemove"];
            if ([polylineIdsToRemove isKindOfClass:[NSArray class]]) {
                [weakSelf removePolylineIds:polylineIdsToRemove];
            }
            result(nil);
        }];
    }
    return self;
}

// 根据 polylineId 获取 polyline 对象
- (nullable AMapPolyline *)polylineForId:(NSString *)polylineId {
    return _polylineDict[polylineId];
}

// 添加一组 polyline 到地图
- (void)addPolylines:(NSArray*)polylinesToAdd {
    for (NSDictionary* polyline in polylinesToAdd) {
        AMapPolyline *polylineModel = [AMapJsonUtils modelFromDict:polyline modelClass:[AMapPolyline class]];
        // 如果有自定义纹理图片，解析图片
        if (polylineModel.customTexture) {
            polylineModel.strokeImage = [AMapConvertUtil imageFromRegistrar:self.registrar iconData:polylineModel.customTexture];
        }
        // 先加入到字段中，避免后续的地图回调里，取不到对应的overlay数据
        if (polylineModel.id_) {
            _polylineDict[polylineModel.id_] = polylineModel;
        }
        [self.mapView addOverlay:polylineModel.polyline];
    }
}

// 修改一组 polyline 的属性
- (void)changePolylines:(NSArray*)polylinesToChange {
    for (NSDictionary* polylineToChange in polylinesToChange) {
        AMapPolyline *polyline = [AMapJsonUtils modelFromDict:polylineToChange modelClass:[AMapPolyline class]];
        AMapPolyline *currentPolyline = _polylineDict[polyline.id_];
        NSAssert(currentPolyline != nil, @"需要修改的Polyline不存在");
        // 如果图片纹理变了，则存储和解析新的图标
        if ([AMapConvertUtil checkIconDescriptionChangedFrom:currentPolyline.customTexture to:polyline.customTexture]) {
            currentPolyline.strokeImage = [AMapConvertUtil imageFromRegistrar:self.registrar iconData:polyline.customTexture];
            currentPolyline.customTexture = polyline.customTexture;
        }
        // 更新除了图标之外的其它信息
        [currentPolyline updatePolyline:polyline];
        MAOverlayRenderer *render = [self.mapView rendererForOverlay:currentPolyline.polyline];
        if (render && [render isKindOfClass:[MAPolylineRenderer class]]) { // render没有复用，只要添加过，就一定可以获取到
            [(MAPolylineRenderer *)render updateRenderWithPolyline:currentPolyline];
        }
    }
}

// 移除一组 polyline
- (void)removePolylineIds:(NSArray*)polylineIdsToRemove {
    for (NSString* polylineId in polylineIdsToRemove) {
        if (!polylineId) {
            continue;
        }
        AMapPolyline* polyline = _polylineDict[polylineId];
        if (!polyline) {
            continue;
        }
        [self.mapView removeOverlay:polyline.polyline];
        [_polylineDict removeObjectForKey:polylineId];
    }
}

//MARK: Polyline的回调

// 处理 polyline 点击事件
- (BOOL)onPolylineTap:(NSString*)polylineId {
    if (!polylineId) {
        return NO;
    }
    AMapPolyline* polyline = _polylineDict[polylineId];
    if (!polyline) {
        return NO;
    }
    [_methodChannel invokeMethod:@"polyline#onTap" arguments:@{@"polylineId" : polylineId}];
    return YES;
}

@end
