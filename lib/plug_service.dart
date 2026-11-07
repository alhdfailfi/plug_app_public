import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tinytuya/tinytuya.dart';

class PlugService {
  static final PlugService _instance = PlugService._internal();
  factory PlugService() => _instance;
  PlugService._internal();

  String _devId = '';
  String _ip = '';
  String _localKey = '';
  bool _configLoaded = false;
  bool _hasSavedConfig = false;

  Future<void> loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    _hasSavedConfig = prefs.containsKey('plug_devId');

    String defaultDevId = '';
    String defaultIp = '';
    String defaultLocalKey = '';

    try {
      final jsonStr = await rootBundle.loadString('config.json');
      final jsonMap = jsonDecode(jsonStr);
      final deviceConfig = jsonMap['device'];
      if (deviceConfig != null) {
        defaultDevId = deviceConfig['devId'] ?? '';
        defaultIp = deviceConfig['ip'] ?? '';
        defaultLocalKey = deviceConfig['localKey'] ?? '';
      }
    } catch (e) {
      print("读取 config.json 失败: $e");
    }

    _devId = prefs.getString('plug_devId') ?? defaultDevId;
    _ip = prefs.getString('plug_ip') ?? defaultIp;
    _localKey = prefs.getString('plug_localKey') ?? defaultLocalKey;
    _configLoaded = true;
  }

  bool get hasSavedConfig => _hasSavedConfig;

  Future<void> saveConfig({
    required String devId,
    required String ip,
    required String localKey,
  }) async {
    _devId = devId.trim();
    _ip = ip.trim();
    _localKey = localKey.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('plug_devId', _devId);
    await prefs.setString('plug_ip', _ip);
    await prefs.setString('plug_localKey', _localKey);
    _hasSavedConfig = true;
  }

  Map<String, String> get currentConfig => {
        'devId': _devId,
        'ip': _ip,
        'localKey': _localKey,
      };

  Future<bool> turnOn() async {
    if (!_configLoaded) await loadConfig();
    if (_devId.isEmpty || _ip.isEmpty || _localKey.isEmpty) return false;
    return _execute((device) => device.turnOn());
  }

  Future<bool> turnOff() async {
    if (!_configLoaded) await loadConfig();
    if (_devId.isEmpty || _ip.isEmpty || _localKey.isEmpty) return false;
    return _execute((device) => device.turnOff());
  }

  Future<bool> _execute(Future<void> Function(Device) action) async {
    Device? device;
    try {
      device = Device(
        deviceId: _devId,
        address: _ip,
        localKey: _localKey,
        version: 3.5,
      );
      await action(device).timeout(const Duration(seconds: 3));
      return true;
    } catch (e) {
      print("❌ 控制失败: $e");
      return false;
    } finally {
      device?.close();
    }
  }

  Future<bool?> fetchStatus() async {
    if (!_configLoaded) await loadConfig();
    if (_devId.isEmpty || _ip.isEmpty || _localKey.isEmpty) return null;
    
    Device? device;
    try {
      device = Device(
        deviceId: _devId,
        address: _ip,
        localKey: _localKey,
        version: 3.5,
      );
      final status = await device.status().timeout(const Duration(seconds: 3));
      final dps = status['dps'];
      if (dps != null && dps['1'] != null) {
        return dps['1'] == true;
      }
    } catch (e) {
      print("❌ 获取状态失败: $e");
    } finally {
      device?.close();
    }
    return null;
  }
}