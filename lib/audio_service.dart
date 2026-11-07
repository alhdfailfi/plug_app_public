import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

class AudioService {
  static final AudioPlayer _player = AudioPlayer();

  static const String _defaultAsset = 'alert.mp3';

  static String? customAudioPath;
  static String? customAudioName;

  static Future<void> init() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
    } catch (e) {
      print("音频初始化失败: $e");
    }
  }

  static Future<void> playAlert() async {
    if (customAudioPath != null && File(customAudioPath!).existsSync()) {
      try {
        await _player.play(DeviceFileSource(customAudioPath!));
        return;
      } catch (e) {
        print("自定义音频播放失败，回退默认: $e");
      }
    }
    try {
      await _player.play(AssetSource(_defaultAsset));
    } catch (e) {
      print("默认音频播放失败，回退系统提示音: $e");
      SystemSound.play(SystemSoundType.alert);
    }
  }
}