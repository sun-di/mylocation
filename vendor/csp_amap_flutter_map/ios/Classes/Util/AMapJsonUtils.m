//
//  MAJsonUtils.m
//  amap_flutter_map
//
//  Created by shaobin on 2019/2/13.
//  Copyright © 2019 Amap.com. All rights reserved.
//

#import "AMapJsonUtils.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <CoreLocation/CoreLocation.h>
#import "AMapConvertUtil.h"

@implementation AMapJsonUtils

/// 判断是否为合法的 JSON 值（字符串、数字或 NSNull）
+ (BOOL)isValidJsonValue:(id)value {
    if([value isKindOfClass:NSString.class] ||
       [value isKindOfClass:NSNumber.class] ||
       value == [NSNull null]) {
        return YES;
    }
    return NO;
}

/// 将任意对象递归转换为 JSON 可序列化对象
+ (id)jsonValueFromObject:(id)obj {
    if([self isValidJsonValue:obj]) {
        return obj;
    }
    if(!obj) {
        return [NSNull null];
    }
    // 常用基本类型转字符串
    if([obj isKindOfClass:NSDate.class] ||
       [obj isKindOfClass:NSData.class] ||
       [obj isKindOfClass:NSValue.class]) {
        NSString *retStr = [NSString stringWithFormat:@"%@", obj];
        return retStr;
    }
    // 数组递归处理
    if([obj isKindOfClass:NSArray.class]) {
        NSArray *oldArray = (NSArray*)obj;
        NSMutableArray *retArray = [NSMutableArray arrayWithCapacity:[oldArray count]];
        for(id item in oldArray) {
            id jsonValue = [self jsonValueFromObject:item];
            [retArray addObject:jsonValue];
        }
        return retArray;
    }
    // 字典递归处理
    if([obj isKindOfClass:NSDictionary.class]) {
        NSDictionary *oldDict = (NSDictionary *)obj;
        NSMutableDictionary *retDict = [NSMutableDictionary dictionaryWithCapacity:[oldDict count]];
        for(id key in [oldDict allKeys]) {
            id item = [oldDict objectForKey:key];
            id jsonValue = [self jsonValueFromObject:item];
            if(jsonValue) {
                [retDict setObject:jsonValue forKey:key];
            }
        }
        return retDict;
    }
    // 自定义对象递归处理属性
    NSArray *propertyArray = [self allPropertiesOfClass:[obj class]];
    NSMutableDictionary *returnDict = [NSMutableDictionary dictionaryWithCapacity:propertyArray.count];
    for(NSString *property in propertyArray) {
        id value = [obj valueForKey:property];
        if(value) {
            id jsonValue = [self jsonValueFromObject:value];
            NSString *mappedName = property;
            if(jsonValue) {
                [returnDict setObject:jsonValue forKey:mappedName];
            }
        }
    }
    return returnDict;
}

/// 将模型对象转换为 JSON 对象（NSDictionary/NSArray），不可序列化时返回 nil
+ (id)jsonObjectFromModel:(id)model {
    id ret = [self jsonValueFromObject:model];
    if(![NSJSONSerialization isValidJSONObject:ret]) {
        return nil;
    }
    return ret;
}

/// 字典转模型对象，支持嵌套、数组、基本类型、UIColor、经纬度等
+ (id)modelFromDict:(NSDictionary*)dict modelClass:(Class)modelClass {
    if(![dict isKindOfClass:[NSDictionary class]]) {
        NSLog(@"[AMap] the object must be of %@", [NSDictionary class]);
        return nil;
    }
    // 如果目标类型本身是 NSDictionary，直接返回副本
    if([modelClass isSubclassOfClass:[NSDictionary class]]) {
        return [dict copy];
    }
    // 获取属性列表
    NSArray *propertyArray = [self allPropertiesOfClass:modelClass];
    NSMutableArray* missedProperties = [NSMutableArray array];
    id ret = [[modelClass alloc] init];
    // 遍历属性并赋值
    for (NSString *propertyName in propertyArray) {
        NSString *keyName = propertyName;
        id value = [dict objectForKey:keyName];
        // 兼容 id 字段
        if(!value && [propertyName isEqualToString:@"id_"]) {
            value = [dict objectForKey:@"id"];
        }
        if(!value) {
            [missedProperties addObject:propertyName];
            continue;
        }
        if(value == [NSNull null]) {
            continue;
        }
        // 获取属性类型
        Class propertyClass = nil;
        objc_property_t property = class_getProperty(modelClass, [propertyName UTF8String]);
        NSString *propertyAttributes = [NSString stringWithCString:property_getAttributes(property) encoding:NSUTF8StringEncoding];
        NSArray *splitPropertyAttributes = [propertyAttributes componentsSeparatedByString:@","];
        if(splitPropertyAttributes.count > 0) {
            NSString *encodeType = splitPropertyAttributes[0];
            if([encodeType hasPrefix:@"T@"]) {
                NSArray *splitEncodeType = [encodeType componentsSeparatedByString:@"\""];
                NSString *className = nil;
                if(splitEncodeType.count > 1) {
                    className = splitEncodeType[1];
                }
                if(className) {
                    propertyClass = NSClassFromString(className);
                }
            } else if ([encodeType isEqualToString:@"T{CLLocationCoordinate2D=dd}"]) {// 经纬度
                // 解析经纬度
                CLLocationCoordinate2D coordinate = [self coordinateFromModel:value];
                // 使用 msgSend 直接设置经纬度属性
                SEL sel = NSSelectorFromString([NSString stringWithFormat:@"set%@:",[propertyName capitalizedString]]);
                ((void (*)(id,SEL,CLLocationCoordinate2D))objc_msgSend)(ret,sel,coordinate);
                continue;
            } else if ([encodeType isEqualToString:@"T{CGPoint=dd}"]) {// CGPoint
                CGPoint point = [AMapConvertUtil pointFromArray:value];
                SEL sel = NSSelectorFromString([NSString stringWithFormat:@"set%@:",[propertyName capitalizedString]]);
                ((void (*)(id,SEL,CGPoint))objc_msgSend)(ret,sel,point);
                continue;
            }
        }
        // 处理属性类型
        if(propertyClass) {
            if([value isKindOfClass:propertyClass]) {
                // 数组类型特殊处理
                if([propertyClass isSubclassOfClass:NSArray.class]) {
                    NSString *elementClassSel = [NSString stringWithFormat:@"%@ElementClass", propertyName];
                    SEL selector = NSSelectorFromString(elementClassSel);
                    if([[ret class] respondsToSelector:selector]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        Class elementCls = [[ret class] performSelector:selector];
#pragma clang diagnostic pop
                        NSArray *arr = (NSArray *)value;
                        NSMutableArray *mutArr = [NSMutableArray arrayWithCapacity:arr.count];
                        for(id item in arr) {
                            id newItem = [self modelFromDict:item modelClass:elementCls];
                            if(newItem) {
                                [mutArr addObject:newItem];
                            } else {
                                [mutArr addObject:item];
                            }
                        }
                        [ret setValue:mutArr forKey:propertyName];
                    } else {
                        [ret setValue:value forKey:propertyName];
                    }
                } else {
                    [ret setValue:value forKey:propertyName];
                }
            } else if([value isKindOfClass:NSDictionary.class]){
                NSDictionary *tempDic = value;
                id model = [self modelFromDict:tempDic modelClass:propertyClass];
                [ret setValue:model forKey:propertyName];
            } else if ([value isKindOfClass:[NSNumber class]] && [NSStringFromClass(propertyClass) isEqualToString:@"UIColor"]) {
                // NSNumber 转 UIColor
                UIColor *color = [AMapConvertUtil colorFromNumber:value];
                [ret setValue:color forKey:propertyName];
            } else {
                [ret setValue:value forKey:propertyName];
#ifdef DEBUG
                Class valueClaz = [value class];
                NSLog(@"\U0001F913\U0001F913 Warning1: property '%@' of %@ is %@, %@ is received", propertyName, modelClass, propertyClass, valueClaz);
#endif
            }
        } else { // 基本类型
            if([self isValidJsonValue:value]){
                [ret setValue:value forKey:propertyName];
            } else {
#ifdef DEBUG
                Class valueClaz = [value class];
                NSLog(@"\U0001F913\U0001F913 Warning1: property '%@' of %@ is %@, %@ is received", propertyName, modelClass, propertyClass, valueClaz);
#endif
            }
        }
    }
#ifdef DEBUG
    if([missedProperties count] > 0) {
        NSLog(@"\U0001F913\U0001F913 Warning2: %@ value missed: %@", modelClass, missedProperties);
    }
#endif
    // 支持模型自定义后处理钩子
    NSString *postHookSel = [NSString stringWithFormat:@"postHookWith:"];
    SEL sel = NSSelectorFromString(postHookSel);
    if([ret respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        [ret performSelector:sel withObject:dict];
#pragma clang diagnostic pop
    }
    return ret;
}

/// 获取类的所有属性名（包含父类）
+ (NSArray<NSString*> *)allPropertiesOfClass:(Class)cls {
    Class clazz = cls;
    NSMutableArray *mutArr = [[NSMutableArray alloc] init];
    while(clazz != [NSObject class]) {
        unsigned int count = 0;
        objc_property_t* properties = class_copyPropertyList(clazz, &count);
        for (int i = 0; i < count ; i++) {
            objc_property_t prop = properties[i];
            NSString *propertyName = [NSString stringWithCString:property_getName(prop) encoding:NSUTF8StringEncoding];
            [mutArr addObject:propertyName];
        }
        if(properties) {
            free(properties);
        }
        clazz = class_getSuperclass(clazz);
    }
    return mutArr;
}

/// 从数据 model 中解析经纬度
+ (CLLocationCoordinate2D)coordinateFromModel:(id)model {
    CLLocationCoordinate2D location = kCLLocationCoordinate2DInvalid;
    if ([model isKindOfClass:[NSArray class]]) {
        return [AMapConvertUtil coordinateFromArray:model];
    } else if ([model isKindOfClass:[NSString class]]) {// 字符串格式（经度，纬度），需逆置
        NSString *coordStr = model;
        NSArray *array = [coordStr componentsSeparatedByString:@","];
        array = [[array reverseObjectEnumerator] allObjects];//逆置
        return [AMapConvertUtil coordinateFromArray:array];
    } else if ([model isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = model;
        NSNumber *latitudeNum = [dict objectForKey:@"latitude"];
        NSNumber *longitudeNum = [dict objectForKey:@"longitude"];
        if (latitudeNum && longitudeNum) {
            location = CLLocationCoordinate2DMake([latitudeNum doubleValue], [longitudeNum doubleValue]);
        } else {
            NSLog(@"经纬度参数异常，解析为无效经纬度");
        }
    }
    return location;
}

@end
