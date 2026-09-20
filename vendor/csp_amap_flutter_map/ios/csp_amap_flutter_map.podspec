#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint csp_amap_flutter_map.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'csp_amap_flutter_map'
  s.version          = '1.0.1'
  s.summary          = '高德地图SDK Flutter插件'
  s.description      = <<-DESC
高德地图SDK Flutter插件，支持Android、iOS、HarmonyOS平台。
                       DESC
  s.homepage         = 'https://github.com/csp/csp_amap_flutter_map'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'CSP' => 'csp@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.dependency 'AMap3DMap'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
