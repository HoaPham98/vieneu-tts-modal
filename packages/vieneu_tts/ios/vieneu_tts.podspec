Pod::Spec.new do |s|
  s.name             = 'vieneu_tts'
  s.version          = '0.1.0'
  s.summary          = 'On-device VieNeu-TTS Flutter plugin'
  s.description      = 'Offline Vietnamese Text-To-Speech powered by audio.cpp and Flutter Rust Bridge'
  s.homepage         = 'https://github.com/HoaPham98/vieneu-tts-modal'
  s.license          = { :type => 'MIT' }
  s.author           = { 'VieNeu Team' => 'support@example.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
