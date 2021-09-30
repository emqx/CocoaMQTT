def import_pods
    pod 'CocoaAsyncSocket', '~> 7.6.3'
    pod 'Starscream', '~> 3.1.1'

end

target :'iOS CocoaMQTT' do
    platform :ios, '10.0'
    use_frameworks!
    import_pods
end

target :'Mac CocoaMQTT'do
    platform :osx, '10.12'
    use_frameworks!
    import_pods
end

target :'tvOS CocoaMQTT' do
    platform :tvos, '10.0'
    use_frameworks!
    import_pods
end