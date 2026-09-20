// CspAmapFlutterMapPlugin 插件主入口，实现 Flutter 插件注册协议

#import "CspAmapFlutterMapPlugin.h"
#import "AMapFlutterFactory.h"

@implementation CspAmapFlutterMapPlugin {
  // 插件注册器，Flutter 与原生通信的桥梁
  NSObject<FlutterPluginRegistrar>* _registrar;
  // MethodChannel，用于 Flutter 与原生方法调用
  FlutterMethodChannel* _channel;
  // 存储所有地图控制器的字典，key 为 viewId
  NSMutableDictionary* _mapControllers;
}

// 插件注册方法，Flutter 调用 registerWithRegistrar 时会执行
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  // 创建地图视图工厂，负责生成原生地图视图
  AMapFlutterFactory* aMapFactory = [[AMapFlutterFactory alloc] initWithRegistrar:registrar];
  // 注册地图视图工厂到 Flutter，指定视图类型标识符
  [registrar registerViewFactory:aMapFactory
                         withId:@"csp_amap_flutter_map"
 gestureRecognizersBlockingPolicy:
    FlutterPlatformViewGestureRecognizersBlockingPolicyWaitUntilTouchesEnded];
}

@end
