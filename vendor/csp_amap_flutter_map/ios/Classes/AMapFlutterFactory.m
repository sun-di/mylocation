//
//  AMapFlutterFactory.m
//  amap_flutter_map
//
//  Created by lly on 2020/10/29.
//

#import "AMapFlutterFactory.h"
#import <MAMapKit/MAMapKit.h>
#import "AMapViewController.h"

// 地图视图工厂实现，负责生成原生地图视图并与 Flutter 通信
@implementation AMapFlutterFactory {
  // 插件注册器，Flutter 与原生通信的桥梁
  NSObject<FlutterPluginRegistrar>* _registrar;
}

// 工厂初始化方法，保存注册器引用
- (instancetype)initWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  self = [super init];
  if (self) {
    _registrar = registrar;
  }
  return self;
}

// 返回参数编解码器，Flutter 与原生通信时使用
- (NSObject<FlutterMessageCodec>*)createArgsCodec {
  return [FlutterStandardMessageCodec sharedInstance];
}

// 创建原生地图视图控制器，并返回给 Flutter
- (NSObject<FlutterPlatformView>*)createWithFrame:(CGRect)frame
                                   viewIdentifier:(int64_t)viewId
                                        arguments:(id _Nullable)args {
    return [[AMapViewController alloc] initWithFrame:frame
                                      viewIdentifier:viewId
                                           arguments:args
                                           registrar:_registrar];
}
@end
