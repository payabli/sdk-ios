Pod::Spec.new do |s|
  s.name             = 'PayabliSDK'
  s.version          = '1.0.0'
  s.summary          = 'Native iOS SDK for Payabli payment acceptance.'
  s.description      = <<-DESC
    PayabliSDK provides drop-in SwiftUI forms for card and ACH tokenization,
    card-not-present payment processing (getpaid), and card-present payments
    via Tap to Pay on iPhone. Part of the Payabli Embedded Components V2 platform.
  DESC

  s.homepage         = 'https://payabli.com'
  s.license          = { :type => 'Commercial', :file => 'LICENSE' }
  s.author           = { 'Payabli' => 'developers@payabli.com' }
  s.source           = { :git => 'https://github.com/payabli/payabli-sdk-ios.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.0'
  s.swift_version         = '5.9'

  s.default_subspecs = 'Core', 'PayIn'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/PayabliSDKCore/**/*.swift'
    core.resource_bundles = {
      'PayabliSDKCore_Privacy' => ['Sources/PayabliSDKCore/Resources/PrivacyInfo.xcprivacy']
    }
    core.frameworks = 'Foundation', 'SwiftUI'
  end

  s.subspec 'PayIn' do |payin|
    payin.source_files = 'Sources/PayabliSDKPayIn/**/*.swift'
    payin.dependency 'PayabliSDK/Core'
    payin.frameworks = 'Foundation', 'SwiftUI', 'UIKit', 'PassKit'
  end
end
