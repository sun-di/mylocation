//
//  AMapViewController.m
//  amap_map
//
//  Created by lly on 2020/10/29.
//

#import "AMapViewController.h"
#import "AMapJsonUtils.h"
#import "AMapCameraPosition.h"
#import "MAMapView+Flutter.h"
#import "MAAnnotationView+Flutter.h"
#import "AMapMarkerController.h"
#import "MAPointAnnotation+Flutter.h"
#import "AMapPolylineController.h"
#import "MAPolyline+Flutter.h"
#import "AMapPolyline.h"
#import "MAPolylineRenderer+Flutter.h"
#import <CoreLocation/CoreLocation.h>
#import "AMapPolygonController.h"
#import "MAPolygon+Flutter.h"
#import "MAPolygonRenderer+Flutter.h"
#import "AMapPolygon.h"
#import <AMapFoundationKit/AMapFoundationKit.h>
#import "AMapLocation.h"
#import "AMapJsonUtils.h"
#import "AMapConvertUtil.h"
#import "FlutterMethodChannel+MethodCallDispatch.h"

// 控制器实现 MAMapViewDelegate 协议
@interface AMapViewController ()<MAMapViewDelegate>

// 地图视图
@property (nonatomic,strong) MAMapView *mapView;
// Flutter 通信通道
@property (nonatomic,strong) FlutterMethodChannel *channel;
// 视图唯一标识
@property (nonatomic,assign) int64_t viewId;
// Flutter 插件注册器
@property (nonatomic,strong) NSObject<FlutterPluginRegistrar>* registrar;

// 覆盖物控制器
@property (nonatomic,strong) AMapMarkerController *markerController;
@property (nonatomic,strong) AMapPolylineController *polylinesController;
@property (nonatomic,strong) AMapPolygonController *polygonsController;

// 地图加载完成前缓存的回调
@property (nonatomic,copy) FlutterResult waitForMapCallBack;
// 地图初始化完成标记
@property (nonatomic,assign) BOOL mapInitCompleted;

// 限制地图显示范围
@property (nonatomic,assign) MAMapRect initLimitMapRect;

@end

@implementation AMapViewController

// 初始化方法
- (instancetype)initWithFrame:(CGRect)frame
               viewIdentifier:(int64_t)viewId
                    arguments:(id _Nullable)args
                    registrar:(NSObject<FlutterPluginRegistrar>*)registrar {
    if (self = [super init]) {
        // 校验参数类型
        NSAssert([args isKindOfClass:[NSDictionary class]], @"传参错误");
        // 构建与 Flutter 通信的 MethodChannel，名称带上 viewId 保证唯一
        NSString* channelName =
        [NSString stringWithFormat:@"csp_amap_flutter_map_%lld", viewId];
        _channel = [FlutterMethodChannel methodChannelWithName:channelName
                                               binaryMessenger:registrar.messenger];
        
        NSDictionary *dict = args;
        
        // 处理 API Key（优先使用 Flutter 传入的 key）
        NSDictionary *apiKey = dict[@"apiKey"];
        if (apiKey && [apiKey isKindOfClass:[NSDictionary class]]) {
            NSString *iosKey = apiKey[@"iosKey"];
            if (iosKey && iosKey.length > 0) {
                [AMapServices sharedServices].apiKey = iosKey;
            }
        }
        // 检查 key 是否设置成功
        NSAssert(([AMapServices sharedServices].apiKey != nil), @"没有设置APIKey，请先设置key");
        
        // 解析初始相机位置
        NSDictionary *cameraDict = [dict objectForKey:@"initialCameraPosition"];
        AMapCameraPosition *cameraPosition = [AMapJsonUtils modelFromDict:cameraDict modelClass:[AMapCameraPosition class]];
        
        _viewId = viewId;
        
        // 隐私合规设置
        if ([dict objectForKey:@"privacyStatement"] != nil) {
            [self updatePrivacyStateWithDict:[dict objectForKey:@"privacyStatement"]];
        }

        // 标记地图初始化未完成
        self.mapInitCompleted = NO;
        // 创建地图视图
        _mapView = [[MAMapView alloc] initWithFrame:frame];
        // SDK 8.1.0 及以上，未调用隐私合规接口会初始化失败
        if (_mapView == nil && (MAMapVersionNumber) >= 80100) {
            NSAssert(_mapView,@"MAMapView初始化失败，地图SDK8.1.0及以上，请务必确保调用SDK任何接口前先调用更新隐私合规updatePrivacyShow:privacyInfo、updatePrivacyAgree两个接口");
        }
        _mapView.delegate = self;
        _mapView.accessibilityElementsHidden = NO;
        // 设置初始相机位置
        [_mapView setCameraPosition:cameraPosition animated:NO duration:0];
        _registrar = registrar;
        // 设置地图参数
        [self.mapView updateMapViewOption:[dict objectForKey:@"options"] withRegistrar:_registrar];
        // 解析限制地图显示范围
        self.initLimitMapRect = [self getLimitMapRectFromOption:[dict objectForKey:@"options"]];
        if (MAMapRectIsEmpty(self.initLimitMapRect) == NO) {// 限制了显示区域，则添加KVO监听
            [_mapView addObserver:self forKeyPath:@"frame" options:0 context:nil];
        }
        
        // 初始化覆盖物控制器
        _markerController = [[AMapMarkerController alloc] init:_channel
                                                       mapView:_mapView
                                                     registrar:registrar];
        _polylinesController = [[AMapPolylineController alloc] init:_channel
                                                            mapView:_mapView
                                                          registrar:registrar];
        _polygonsController = [[AMapPolygonController alloc] init:_channel
                                                          mapView:_mapView
                                                        registrar:registrar];
        // 添加初始 marker
        id markersToAdd = args[@"markersToAdd"];
        if ([markersToAdd isKindOfClass:[NSArray class]]) {
            [_markerController addMarkers:markersToAdd];
        }
        // 添加初始 polyline
        id polylinesToAdd = args[@"polylinesToAdd"];
        if ([polylinesToAdd isKindOfClass:[NSArray class]]) {
            [_polylinesController addPolylines:polylinesToAdd];
        }
        // 添加初始 polygon
        id polygonsToAdd = args[@"polygonsToAdd"];
        if ([polygonsToAdd isKindOfClass:[NSArray class]]) {
            [_polygonsController addPolygons:polygonsToAdd];
        }
        
        // 设置 Flutter 方法通道的回调处理
        [self setMethodCallHandler];
    }
    return self;
}

- (UIView*)view {
    return _mapView;
}

- (void)dealloc {
    if (MAMapRectIsEmpty(_initLimitMapRect) == NO) {//避免没有开始渲染，frame监听还存在时，快速销毁
        [_mapView removeObserver:self forKeyPath:@"frame"];
    }
}

- (void)updatePrivacyStateWithDict:(NSDictionary *)dict {
    if ((MAMapVersionNumber) < 80100) {
        NSLog(@"当前地图SDK版本没有隐私合规接口，请升级地图SDK到8.1.0及以上版本");
        return;
    }
    if (dict == nil || [dict isKindOfClass:[NSDictionary class]] == NO) {
        return;
    }
    if (dict[@"hasContains"] != nil && dict[@"hasShow"] != nil) {
        [MAMapView updatePrivacyShow:[dict[@"hasShow"] integerValue] privacyInfo:[dict[@"hasContains"] integerValue]];
    }
    if (dict[@"hasAgree"] != nil) {
        [MAMapView updatePrivacyAgree:[dict[@"hasAgree"] integerValue]];
    }
}

- (MAMapRect)getLimitMapRectFromOption:(NSDictionary *)dict {
    NSArray *limitBounds = dict[@"limitBounds"];
    if (limitBounds) {
        return [AMapConvertUtil mapRectFromArray:limitBounds];
    } else {
        return MAMapRectMake(0, 0, 0, 0);
    }
}

- (void)observeValueForKeyPath:(NSString*)keyPath
                      ofObject:(id)object
                        change:(NSDictionary*)change
                       context:(void*)context {
    if (MAMapRectIsEmpty(self.initLimitMapRect) == YES ) {//初始化时，没有设置显示范围，则不再监听frame的变化
        [_mapView removeObserver:self forKeyPath:@"frame"];
        return;
    }
    if (object == _mapView && [keyPath isEqualToString:@"frame"]) {
        CGRect bounds = _mapView.bounds;
        if (CGRectEqualToRect(bounds, CGRectZero)) {
            // 忽略初始化时，frame为0的情况，仅当frame更新为非0时，才设置limitRect
            return;
        }
        //监听到一次，就直接移除KVO
        [_mapView removeObserver:self forKeyPath:@"frame"];
        if (MAMapRectIsEmpty(self.initLimitMapRect) == NO) {
            //加0.1s的延迟，确保地图的frame和内部引擎都已经更新
            MAMapRect tempLimitMapRect = self.initLimitMapRect;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                self.mapView.limitMapRect = tempLimitMapRect;
            });
            //避免KVO短时间触发多次，造成多次延迟派发
            self.initLimitMapRect = MAMapRectMake(0, 0, 0, 0);
        }
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}


- (void)setMethodCallHandler {
    __weak __typeof__(self) weakSelf = self;
    [self.channel addMethodName:@"map#update" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        [weakSelf.mapView updateMapViewOption:call.arguments[@"options"] withRegistrar:weakSelf.registrar];
        result(nil);
    }];
    [self.channel addMethodName:@"map#waitForMap" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        if (weakSelf.mapInitCompleted) {
            result(nil);
        } else {
            weakSelf.waitForMapCallBack = result;
        }
    }];
    [self.channel addMethodName:@"camera#move" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        [weakSelf.mapView setCameraUpdateDict:call.arguments];
        result(nil);
    }];
    [self.channel addMethodName:@"map#takeSnapshot" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        [weakSelf.mapView takeSnapshotInRect:weakSelf.mapView.frame withCompletionBlock:^(UIImage *resultImage, NSInteger state) {
            if (state == 1 && resultImage) {
                NSData *data = UIImagePNGRepresentation(resultImage);
                result([FlutterStandardTypedData typedDataWithBytes:data]);
            } else if (state == 0) {
                NSLog(@"takeSnapsShot 载入不完整");
            }
        }];
    }];
    [self.channel addMethodName:@"map#setRenderFps" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        NSInteger fps = [call.arguments[@"fps"] integerValue];
        [weakSelf.mapView setMaxRenderFrame:fps];
        result(nil);
    }];
    [self.channel addMethodName:@"map#contentApprovalNumber" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        NSString *approvalNumber = [weakSelf.mapView mapContentApprovalNumber];
        result(approvalNumber);
    }];
    [self.channel addMethodName:@"map#satelliteImageApprovalNumber" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        NSString *sateApprovalNumber = [weakSelf.mapView satelliteImageApprovalNumber];
        result(sateApprovalNumber);
    }];
    [self.channel addMethodName:@"map#clearDisk" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        [weakSelf.mapView clearDisk];
        result(nil);
    }];
    [self.channel addMethodName:@"map#toScreenCoordinate" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        CLLocationCoordinate2D location = [AMapConvertUtil coordinateFromArray:call.arguments];
        CGPoint point = [weakSelf.mapView convertCoordinate:location toPointToView:weakSelf.mapView];
        result([AMapConvertUtil dictionaryFromPoint:point]);
    }];
    [self.channel addMethodName:@"map#fromScreenCoordinate" withHandler:^(FlutterMethodCall * _Nonnull call, FlutterResult  _Nonnull result) {
        CGPoint point = [AMapConvertUtil pointFromDictionary:call.arguments];
        CLLocationCoordinate2D coordinate = [weakSelf.mapView convertPoint:point toCoordinateFromView:weakSelf.mapView];
        result([AMapConvertUtil arrayFromLocation:coordinate]);
    }];
}

//MARK: MAMapViewDelegate

//MARK: 定位相关回调

- (void)mapView:(MAMapView *)mapView didChangeUserTrackingMode:(MAUserTrackingMode)mode animated:(BOOL)animated {
    NSLog(@"%s,mapView:%@ mode:%ld",__func__,mapView,(long)mode);
}
/**
 * @brief 在地图View将要启动定位时，会调用此函数
 * @param mapView 地图View
 */
- (void)mapViewWillStartLocatingUser:(MAMapView *)mapView {
    NSLog(@"%s,mapView:%@",__func__,mapView);
}

/**
 * @brief 在地图View停止定位后，会调用此函数
 * @param mapView 地图View
 */
- (void)mapViewDidStopLocatingUser:(MAMapView *)mapView {
    NSLog(@"%s,mapView:%@",__func__,mapView);
}

/**
 * @brief 位置或者设备方向更新后，会调用此函数
 * @param mapView 地图View
 * @param userLocation 用户定位信息(包括位置与设备方向等数据)
 * @param updatingLocation 标示是否是location数据更新, YES:location数据更新 NO:heading数据更新
 */
- (void)mapView:(MAMapView *)mapView didUpdateUserLocation:(MAUserLocation *)userLocation updatingLocation:(BOOL)updatingLocation {
    if (updatingLocation && userLocation.location) {
        AMapLocation *location = [[AMapLocation alloc] init];
        [location updateWithUserLocation:userLocation.location];
        NSDictionary *jsonObjc = [AMapJsonUtils jsonObjectFromModel:location];
        NSArray *latlng = [AMapConvertUtil jsonArrayFromCoordinate:location.latLng];
        NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithDictionary:jsonObjc];
        [dict setValue:latlng forKey:@"latLng"];
        [_channel invokeMethod:@"location#changed" arguments:@{@"location" : dict}];
    }
}

/**
 *  @brief 当plist配置NSLocationAlwaysUsageDescription或者NSLocationAlwaysAndWhenInUseUsageDescription，并且[CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined，会调用代理的此方法。
 此方法实现调用后台权限API即可（ 该回调必须实现 [locationManager requestAlwaysAuthorization] ）; since 6.8.0
 *  @param locationManager  地图的CLLocationManager。
 */
- (void)mapViewRequireLocationAuth:(CLLocationManager *)locationManager {
    if ([CLLocationManager authorizationStatus] == kCLAuthorizationStatusNotDetermined) {
        [locationManager requestAlwaysAuthorization];
    }
}

/**
 * @brief 定位失败后，会调用此函数
 * @param mapView 地图View
 * @param error 错误号，参考CLError.h中定义的错误号
 */
- (void)mapView:(MAMapView *)mapView didFailToLocateUserWithError:(NSError *)error {
    NSLog(@"%s,mapView:%@ error:%@",__func__,mapView,error);
}


/**
 * @brief 地图加载成功
 * @param mapView 地图View
 */
- (void)mapViewDidFinishLoadingMap:(MAMapView *)mapView {
    NSLog(@"%s,mapView:%@",__func__,mapView);
}

- (void)mapInitComplete:(MAMapView *)mapView {
    NSLog(@"%s,mapView:%@",__func__,mapView);
    self.mapInitCompleted = YES;
    if (self.waitForMapCallBack) {
        self.waitForMapCallBack(nil);
        self.waitForMapCallBack = nil;
    }
}

//MARK: Annotation相关回调

- (MAAnnotationView *)mapView:(MAMapView *)mapView viewForAnnotation:(id<MAAnnotation>)annotation {
    if ([annotation isKindOfClass:[MAPointAnnotation class]] == NO) {
        return nil;
    }
    MAPointAnnotation *fAnno = annotation;
    if (fAnno.markerId == nil) {
        return nil;
    }
    AMapMarker *marker = [_markerController markerForId:fAnno.markerId];
    //    TODO: 这里只实现基础AnnotationView，不再根据marker的数据差异，区分是annotationView还是pinAnnotationView了；
    MAAnnotationView *view = [mapView dequeueReusableAnnotationViewWithIdentifier:AMapFlutterAnnotationViewIdentifier];
    if (view == nil) {
        view = [[MAAnnotationView alloc] initWithAnnotation:annotation reuseIdentifier:AMapFlutterAnnotationViewIdentifier];
    }
    [view updateViewWithMarker:marker];
    return view;
}

/**
 * @brief 当mapView新添加annotation views时，调用此接口
 * @param mapView 地图View
 * @param views 新添加的annotation views
 */
- (void)mapView:(MAMapView *)mapView didAddAnnotationViews:(NSArray *)views {
    for (MAAnnotationView *view in views) {
        if ([view.annotation isKindOfClass:[MAAnnotationView class]] == NO) {
            return;
        }
        MAPointAnnotation *fAnno = view.annotation;
        if (fAnno.markerId == nil) {
            return;
        }
        AMapMarker *marker = [_markerController markerForId:fAnno.markerId];
        [view updateViewWithMarker:marker];
    }
}


/**
 * @brief 标注view的calloutview整体点击时，触发该回调。只有使用默认calloutview时才生效。
 * @param mapView 地图的view
 * @param view calloutView所属的annotationView
 */
//- (void)mapView:(MAMapView *)mapView didAnnotationViewCalloutTapped:(MAAnnotationView *)view {
//    MAPointAnnotation *fAnno = view.annotation;
//    if (fAnno.markerId == nil) {
//        return;
//    }
//    [_markerController onInfoWindowTap:fAnno.markerId];
//}

/**
 * @brief 标注view被点击时，触发该回调。（since 5.7.0）
 * @param mapView 地图的view
 * @param view annotationView
 */
- (void)mapView:(MAMapView *)mapView didAnnotationViewTapped:(MAAnnotationView *)view {
    MAPointAnnotation *fAnno = view.annotation;
    if (fAnno.markerId == nil) {
        return;
    }
    [_markerController onMarkerTap:fAnno.markerId];
}

/**
 * @brief 拖动annotation view时view的状态变化
 * @param mapView 地图View
 * @param view annotation view
 * @param newState 新状态
 * @param oldState 旧状态
 */
- (void)mapView:(MAMapView *)mapView annotationView:(MAAnnotationView *)view didChangeDragState:(MAAnnotationViewDragState)newState
   fromOldState:(MAAnnotationViewDragState)oldState {
    if (newState == MAAnnotationViewDragStateEnding) {
        MAPointAnnotation *fAnno = view.annotation;
        if (fAnno.markerId == nil) {
            return;
        }
        [_markerController onMarker:fAnno.markerId endPostion:fAnno.coordinate];
    }
}

/**
 * @brief 根据overlay生成对应的Renderer
 * @param mapView 地图View
 * @param overlay 指定的overlay
 * @return 生成的覆盖物Renderer
 */
- (MAOverlayRenderer *)mapView:(MAMapView *)mapView rendererForOverlay:(id <MAOverlay>)overlay {
    if ([overlay isKindOfClass:[MAPolyline class]]) {
        MAPolyline *polyline = overlay;
        if (polyline.polylineId == nil) {
            return nil;
        }
        AMapPolyline *fPolyline = [_polylinesController polylineForId:polyline.polylineId];
        MAPolylineRenderer *polylineRenderer = [[MAPolylineRenderer alloc] initWithPolyline:overlay];
        [polylineRenderer updateRenderWithPolyline:fPolyline];
        return polylineRenderer;
    } else if ([overlay isKindOfClass:[MAPolygon class]]) {
        MAPolygon *polygon = overlay;
        if (polygon.polygonId == nil) {
            return nil;
        }
        AMapPolygon *fPolygon = [_polygonsController polygonForId:polygon.polygonId];
        MAPolygonRenderer *polygonRenderer = [[MAPolygonRenderer alloc] initWithPolygon:polygon];
        [polygonRenderer updateRenderWithPolygon:fPolygon];
        return polygonRenderer;
    } else {
        return nil;
    }
}

/**
 * @brief 单击地图回调，返回经纬度
 * @param mapView 地图View
 * @param coordinate 经纬度
 */
- (void)mapView:(MAMapView *)mapView didSingleTappedAtCoordinate:(CLLocationCoordinate2D)coordinate {
    NSArray *latLng = [AMapConvertUtil jsonArrayFromCoordinate:coordinate];
    [_channel invokeMethod:@"map#onTap" arguments:@{@"latLng":latLng}];
    NSArray *polylineRenderArray = [mapView getHittedPolylinesWith:coordinate traverseAll:NO];
    if (polylineRenderArray && polylineRenderArray.count > 0) {
        MAOverlayRenderer *render = polylineRenderArray.firstObject;
        MAPolyline *polyline = render.overlay;
        if (polyline.polylineId) {
            [_polylinesController onPolylineTap:polyline.polylineId];
        }
    }
}

/**
 * @brief 长按地图，返回经纬度
 * @param mapView 地图View
 * @param coordinate 经纬度
 */
- (void)mapView:(MAMapView *)mapView didLongPressedAtCoordinate:(CLLocationCoordinate2D)coordinate {
    NSArray *latLng = [AMapConvertUtil jsonArrayFromCoordinate:coordinate];
    [_channel invokeMethod:@"map#onLongPress" arguments:@{@"latLng":latLng}];
}

/**
 * @brief 当touchPOIEnabled == YES时，单击地图使用该回调获取POI信息
 * @param mapView 地图View
 * @param pois 获取到的poi数组(由MATouchPoi组成)
 */
- (void)mapView:(MAMapView *)mapView didTouchPois:(NSArray *)pois {
    MATouchPoi *poi = pois.firstObject;
    NSDictionary *dict = [AMapConvertUtil dictFromTouchPOI:poi];
    if (dict) {
        [_channel invokeMethod:@"map#onPoiTouched" arguments:@{@"poi":dict}];
    }
}

/**
 * @brief 地图区域改变过程中会调用此接口 since 4.6.0
 * @param mapView 地图View
 */
- (void)mapViewRegionChanged:(MAMapView *)mapView {
//    TODO: 这里消息回调太多，channel可能有性能影响
    AMapCameraPosition *cameraPos = [mapView getCurrentCameraPosition];
    NSDictionary *dict = [cameraPos toDictionary];
    if (dict) {
        [_channel invokeMethod:@"camera#onMove" arguments:@{@"position":dict}];
    }
}

/**
 * @brief 地图区域改变完成后会调用此接口
 * @param mapView 地图View
 * @param animated 是否动画
 */
- (void)mapView:(MAMapView *)mapView regionDidChangeAnimated:(BOOL)animated {
    AMapCameraPosition *cameraPos = [mapView getCurrentCameraPosition];
    NSDictionary *dict = [cameraPos toDictionary];
    if (dict) {
        [_channel invokeMethod:@"camera#onMoveEnd" arguments:@{@"position":dict}];
    }
}

@end
