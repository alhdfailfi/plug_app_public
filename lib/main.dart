import 'dart:async';
import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'plug_service.dart';
import 'audio_service.dart';
import 'notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AudioService.init();
  await NotificationService.init();
  await PlugService().loadConfig();
  runApp(const PlugApp());
}

class PlugApp extends StatelessWidget {
  const PlugApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '涂鸦智能插座控制',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final PlugService _plug = PlugService();
  final Battery _battery = Battery();

  bool _isOn = false;
  bool _isLoading = false;
  bool? _pendingTarget;
  int _batteryLevel = -1;
  bool _isCharging = false;

  bool _autoBattery = false;
  int _batteryMin = 30;
  int _batteryMax = 70;
  String _batteryOnOp = '<=';
  String _batteryOffOp = '>=';

  bool _timerEnabled = false;
  int _timerMinutes = 30;
  int _remainingSeconds = 0;
  String _timerAction = '关闭插座';
  DateTime? _timerEndAt;
  Timer? _countdownTimer;

  bool _audioEnabled = false;
  bool _notifyEnabled = true;

  bool _timerExpanded = true;
  bool _batteryExpanded = true;
  bool _audioExpanded = true;

  Timer? _globalTimer;
  StreamSubscription<BatteryState>? _batterySubscription;

  DateTime? _lastAutoSendTime;
  bool? _lastAutoSendTarget;

  bool? _deviceOnline;
  DateTime? _lastCommTime;
  int _offlineCount = 0;
  int _commVersion = 0;

  static const List<String> _opOptions = ['>=', '>', '<=', '<', '=='];

  @override
  void initState() {
    super.initState();
    _loadBasicSettings();
    _refreshPlugStatus();
    _initBattery();

    _globalTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      await _updateBatteryLevel();
      await _refreshPlugStatus(silent: true);
      await _checkBasicBatteryThreshold();
      await _checkCountdownTimeout();
    });
  }

  @override
  void dispose() {
    _globalTimer?.cancel();
    _countdownTimer?.cancel();
    _batterySubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadBasicSettings() async {
    final prefs = await SharedPreferences.getInstance();

    int min = (prefs.getInt('batteryMin') ?? 30).clamp(0, 99);
    int max = (prefs.getInt('batteryMax') ?? 70).clamp(1, 100);
    if (min >= max) {
      if (max <= 1) {
        max = 2;
        min = 1;
      } else {
        min = max - 1;
      }
    }

    setState(() {
      _autoBattery = prefs.getBool('autoBattery') ?? false;
      _batteryMin = min;
      _batteryMax = max;
      _batteryOnOp = prefs.getString('batteryOnOp') ?? '<=';
      _batteryOffOp = prefs.getString('batteryOffOp') ?? '>=';
      _timerEnabled = prefs.getBool('timerEnabled') ?? false;
      _audioEnabled = prefs.getBool('audioEnabled') ?? false;
      _notifyEnabled = prefs.getBool('notifyEnabled') ?? true;
      AudioService.customAudioPath = prefs.getString('customAudioPath');
      AudioService.customAudioName = prefs.getString('customAudioName');
    });
  }

  Future<void> _saveBasicSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoBattery', _autoBattery);
    await prefs.setInt('batteryMin', _batteryMin);
    await prefs.setInt('batteryMax', _batteryMax);
    await prefs.setString('batteryOnOp', _batteryOnOp);
    await prefs.setString('batteryOffOp', _batteryOffOp);
    await prefs.setBool('timerEnabled', _timerEnabled);
    await prefs.setBool('audioEnabled', _audioEnabled);
    await prefs.setBool('notifyEnabled', _notifyEnabled);
  }

  Future<void> _pickAudio() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result != null && result.files.single.path != null) {
        final file = result.files.single;
        setState(() {
          AudioService.customAudioPath = file.path!;
          AudioService.customAudioName = file.name;
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('customAudioPath', file.path!);
        await prefs.setString('customAudioName', file.name);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('音频已选择: ${file.name}')));
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('选择文件失败')));
    }
  }

  Future<void> _clearAudio() async {
    setState(() {
      AudioService.customAudioPath = null;
      AudioService.customAudioName = null;
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('customAudioPath');
    await prefs.remove('customAudioName');
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已恢复内置默认提示音')));
  }

  Future<void> _updateBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      final charging = state == BatteryState.charging || state == BatteryState.full;
      if (mounted && (level != _batteryLevel || charging != _isCharging)) {
        setState(() {
          _batteryLevel = level;
          _isCharging = charging;
        });
      }
    } catch (e) {
      debugPrint('无法获取电量');
    }
  }

  void _initBattery() async {
    await _updateBatteryLevel();
    _batterySubscription = _battery.onBatteryStateChanged.listen((_) => _updateBatteryLevel());
  }

  void _showInAppBanner(String message, {IconData icon = Icons.notifications_active, Color? color}) {
    if (!_notifyEnabled || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: color ?? Colors.blueGrey.shade700,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
  }

  void _fireAlert(String message, {IconData icon = Icons.notifications_active, Color? color}) {
    if (_audioEnabled) AudioService.playAlert();
    _showInAppBanner(message, icon: icon, color: color);
    if (_notifyEnabled) {
      NotificationService.show('智能插座提醒', message);
    }
  }

  String _opLabel(String op) {
    switch (op) {
      case '<=': return '≤';
      case '<': return '<';
      case '==': return '=';
      case '>=': return '≥';
      case '>': return '>';
      default: return op;
    }
  }

  bool _evalOp(int level, String op, int threshold) {
    switch (op) {
      case '<=': return level <= threshold;
      case '<': return level < threshold;
      case '==': return level == threshold;
      case '>=': return level >= threshold;
      case '>': return level > threshold;
      default: return false;
    }
  }

  Future<void> _checkBasicBatteryThreshold() async {
    if (!_autoBattery || _batteryLevel <= 0) return;
    if (_pendingTarget != null) return;

    bool canSend(bool target) {
      if (_lastAutoSendTarget == target && _lastAutoSendTime != null) {
        if (DateTime.now().difference(_lastAutoSendTime!) < const Duration(seconds: 60)) {
          return false;
        }
      }
      return true;
    }

    if (!_isOn && _evalOp(_batteryLevel, _batteryOnOp, _batteryMin) && canSend(true)) {
      _lastAutoSendTime = DateTime.now();
      _lastAutoSendTarget = true;
      final ok = await _toggle(true);
      if (ok && mounted) {
        _fireAlert(
          '电量 $_batteryLevel% ${_opLabel(_batteryOnOp)} $_batteryMin%，已自动开启插座',
          icon: Icons.battery_charging_full,
          color: Colors.green.shade700,
        );
      }
    } else if (_isOn && _evalOp(_batteryLevel, _batteryOffOp, _batteryMax) && canSend(false)) {
      _lastAutoSendTime = DateTime.now();
      _lastAutoSendTarget = false;
      final ok = await _toggle(false);
      if (ok && mounted) {
        _fireAlert(
          '电量 $_batteryLevel% ${_opLabel(_batteryOffOp)} $_batteryMax%，已自动关闭插座',
          icon: Icons.battery_full,
          color: Colors.red.shade700,
        );
      }
    }
  }

  Future<void> _refreshPlugStatus({bool silent = false}) async {
    if (_pendingTarget != null) return;
    if (!silent) setState(() => _isLoading = true);
    
    final myVersion = _commVersion;
    final status = await _plug.fetchStatus();
    
    if (!mounted) return;

    if (_commVersion != myVersion) {
      if (!silent) setState(() => _isLoading = false);
      return;
    }

    final oldOnline = _deviceOnline;
    final oldIsOn = _isOn;

    if (status != null) {
      _offlineCount = 0;
      _deviceOnline = true;
      _isOn = status;
      _lastCommTime = DateTime.now();
    } else {
      _offlineCount++;
      if (_offlineCount >= 2) {
        _deviceOnline = false;
      }
    }

    final stateChanged = (oldOnline != _deviceOnline) || (oldIsOn != _isOn);
    
    if (stateChanged || !silent) {
      setState(() {
        if (!silent) _isLoading = false;
      });
    }
  }

  Future<bool> _toggle(bool turnOn, {bool fromUser = false}) async {
    if (fromUser && _pendingTarget != null) return false;
    setState(() => _pendingTarget = turnOn);
    final success = turnOn ? await _plug.turnOn() : await _plug.turnOff();
    
    if (mounted) {
      setState(() {
        if (success) {
          _commVersion++; 
          _offlineCount = 0;
          _deviceOnline = true;
          _isOn = turnOn;
          _lastCommTime = DateTime.now();
        } else {
          _offlineCount = 2;
          _deviceOnline = false;
        }
        _pendingTarget = null;
      });
      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('连接超时或指令发送失败，请检查插座是否在线'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) _refreshPlugStatus(silent: true);
        });
      }
    }
    return success;
  }

  void _startTimer() {
    if (!_timerEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先开启「快捷倒计时」功能')));
      return;
    }
    if (_timerEndAt != null) return;

    final end = DateTime.now().add(Duration(minutes: _timerMinutes));
    setState(() {
      _timerEndAt = end;
      _remainingSeconds = _timerMinutes * 60;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final e = _timerEndAt;
      if (e == null) { timer.cancel(); return; }
      final remain = e.difference(DateTime.now()).inSeconds;
      if (remain <= 0) {
        timer.cancel();
        _executeTimerAction();
      } else {
        if (mounted) setState(() => _remainingSeconds = remain);
      }
    });
  }

  Future<void> _checkCountdownTimeout() async {
    final end = _timerEndAt;
    if (end == null) return;
    if (DateTime.now().isAfter(end)) {
      await _executeTimerAction();
    }
  }

  Future<void> _executeTimerAction() async {
    if (_timerEndAt == null) return;
    _countdownTimer?.cancel();

    final action = _timerAction;
    setState(() {
      _timerEndAt = null;
      _remainingSeconds = 0;
    });

    bool success = true;
    if (action == '关闭插座' && _isOn) success = await _toggle(false);
    if (action == '开启插座' && !_isOn) success = await _toggle(true);

    if (!mounted) return;
    if (success) {
      _fireAlert(
        '定时任务已完成：$action',
        icon: Icons.timer,
        color: Colors.blue.shade700,
      );
    } else {
      _fireAlert(
        '定时任务执行失败：$action（插座离线或超时）',
        icon: Icons.error_outline,
        color: Colors.red.shade700,
      );
    }
  }

  void _cancelTimer() {
    _countdownTimer?.cancel();
    setState(() {
      _timerEndAt = null;
      _remainingSeconds = 0;
    });
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已取消倒计时')));
  }

  Future<void> _launchWeb(String url) async {
    final uri = Uri.parse(url);
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法打开链接，请检查设备是否安装了浏览器')));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('跳转失败: $e')));
      }
    }
  }

  void _openAboutPage() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '关于涂鸦智能插座控制',
                  maxLines: 1,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('版本：1.0.0+1', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            const Text(
              '• 涂鸦 WiFi 智能插座，纯本地局域网 TCP 直连，保护隐私，不依赖云端。\n'
              '• 支持实时电量监控与自动阈值保护。\n'
              '• 内置快捷倒计时任务。\n'
              '• 支持自定义提示音与系统通知震动提醒。',
              style: TextStyle(fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 8),
            const Text(
              '🔌 适用设备：涂鸦 WiFi 智能插座标准版',
              style: TextStyle(fontSize: 14, color: Colors.teal, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            const Text('👤 作者：shgvge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('🤖 代码生成：由 DeepSeek 提供支持', style: TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey.shade800,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.code, size: 18),
                    label: const Text('GitHub 主页', style: TextStyle(fontSize: 13)),
                    onPressed: () => _launchWeb('https://github.com/alhdfailfi/plug_app_public'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.pink.shade400,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.play_circle_fill, size: 18),
                    label: const Text('B站主页', style: TextStyle(fontSize: 13)),
                    onPressed: () => _launchWeb('https://space.bilibili.com/1539184586'),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _openConnectionSettings() async {
    final cfg = _plug.currentConfig;
    final devIdCtrl = TextEditingController(text: cfg['devId']);
    final ipCtrl = TextEditingController(text: cfg['ip']);
    final keyCtrl = TextEditingController(text: cfg['localKey']);

    bool saving = false;
    bool obscureKey = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('插座连接设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_plug.hasSavedConfig)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade800, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '请填入涂鸦设备的 Device ID、局域网 IP 和 Local Key。',
                            style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                TextField(
                  controller: devIdCtrl,
                  enabled: !saving,
                  decoration: const InputDecoration(
                    labelText: 'Device ID',
                    hintText: '涂鸦设备 ID（20 位）',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: ipCtrl,
                  enabled: !saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'IP 地址',
                    hintText: '如 192.168.1.90',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: keyCtrl,
                  enabled: !saving,
                  obscureText: obscureKey,
                  decoration: InputDecoration(
                    labelText: 'Local Key',
                    hintText: '涂鸦设备密钥',
                    suffixIcon: IconButton(
                      icon: Icon(
                        obscureKey ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () {
                        setDialogState(() => obscureKey = !obscureKey);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setDialogState(() => saving = true);

                      await _plug.saveConfig(
                        devId: devIdCtrl.text,
                        ip: ipCtrl.text,
                        localKey: keyCtrl.text,
                      );

                      bool? result;
                      bool timedOut = false;
                      try {
                        result = await _plug.fetchStatus().timeout(const Duration(seconds: 5));
                      } on TimeoutException {
                        timedOut = true;
                      } catch (_) {}

                      if (ctx.mounted) Navigator.pop(ctx);

                      if (!mounted) return;
                      final messenger = ScaffoldMessenger.of(this.context);
                      if (timedOut) {
                        messenger.showSnackBar(SnackBar(
                          content: const Text('连接超时（5 秒无响应），请检查 IP 和 WiFi'),
                          backgroundColor: Colors.orange.shade700,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ));
                      } else if (result != null) {
                        setState(() {
                          _isOn = result!;
                          _deviceOnline = true;
                          _offlineCount = 0;
                          _lastCommTime = DateTime.now();
                          _commVersion++;
                        });
                        messenger.showSnackBar(const SnackBar(
                          content: Text('配置已保存，连接成功'),
                          behavior: SnackBarBehavior.floating,
                        ));
                      } else {
                        setState(() {
                          _deviceOnline = false;
                          _offlineCount = 2;
                        });
                        messenger.showSnackBar(SnackBar(
                          content: const Text('配置已保存，但连接失败，请检查 IP / Local Key'),
                          backgroundColor: Colors.red.shade700,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ));
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final ip = _plug.currentConfig['ip'] ?? '';
    final display = ip.isEmpty ? '未配置' : ip;
    return Tooltip(
      message: ip.isEmpty ? '插座 IP 未配置，请点击右上角设置' : '插座 IP：$ip',
      child: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: _buildTitle(),
          centerTitle: true,
          leadingWidth: 100,
          leading: Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusBadge(),
                const SizedBox(width: 8),
                _buildConnectionDot(),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.info_outline),
              tooltip: '关于',
              onPressed: _openAboutPage,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              tooltip: '插座连接设置',
              onPressed: _openConnectionSettings,
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '刷新状态',
              onPressed: () => _refreshPlugStatus(),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: '手动控制', icon: Icon(Icons.touch_app)),
              Tab(text: '定时与阈值', icon: Icon(Icons.timer)),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _KeepAlive(child: _buildControlPage()),
            _KeepAlive(child: _buildBasicSettingsPage()),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final on = _isOn;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: on ? Colors.green.shade600 : Colors.grey.shade500,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: (on ? Colors.green : Colors.grey).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(on ? Icons.power : Icons.power_off, color: Colors.white, size: 16),
          const SizedBox(width: 3),
          Text(on ? '开' : '关',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildConnectionDot() {
    Color color;
    String tooltip;
    
    if (_isLoading) {
      color = Colors.amber;
      tooltip = '正在刷新连接…';
    } else if (_deviceOnline == null) {
      color = Colors.grey;
      tooltip = '连接状态未知';
    } else if (_deviceOnline == true) {
      color = Colors.green;
      final ago = _lastCommTime != null
          ? '${DateTime.now().difference(_lastCommTime!).inSeconds} 秒前'
          : '';
      tooltip = '插座在线${ago.isNotEmpty ? '，最后通信 $ago' : ''}';
    } else {
      color = Colors.red;
      tooltip = '插座离线，请检查 WiFi / IP';
    }
    
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.5),
              blurRadius: 4,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlPage() {
    if (_isLoading && _pendingTarget == null) {
      return const Center(child: CircularProgressIndicator());
    }

    final pending = _pendingTarget;
    final displayOn = pending ?? _isOn;
    final isBusy = pending != null;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Icon(
              isBusy ? Icons.sync : (displayOn ? Icons.power : Icons.power_off),
              key: ValueKey('icon-${isBusy ? 'busy' : displayOn}'),
              size: 100,
              color: isBusy ? Colors.blue : (displayOn ? Colors.green : Colors.grey),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              isBusy
                  ? (pending ? '正在开启…' : '正在关闭…')
                  : (displayOn ? '插座已开启' : '插座已关闭'),
              key: ValueKey('text-${isBusy ? pending : displayOn}'),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: isBusy ? Colors.blue : (displayOn ? Colors.green : Colors.grey[700]),
              ),
            ),
          ),
          const SizedBox(height: 40),
          _buildToggleBar(),
        ],
      ),
    );
  }

  Widget _buildToggleBar() {
    final target = _pendingTarget;
    final displayOn = target ?? _isOn;

    return Container(
      width: 260, height: 70,
      decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(35)),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleHalf(
              label: 'OFF',
              active: !displayOn,
              pending: target == false,
              activeColor: Colors.red,
              onTap: target == null ? () => _toggle(false, fromUser: true) : null,
            ),
          ),
          Expanded(
            child: _buildToggleHalf(
              label: 'ON',
              active: displayOn,
              pending: target == true,
              activeColor: Colors.green,
              onTap: target == null ? () => _toggle(true, fromUser: true) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleHalf({
    required String label,
    required bool active,
    required bool pending,
    required Color activeColor,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: active ? activeColor.withOpacity(pending ? 0.45 : 1.0) : Colors.transparent,
          borderRadius: BorderRadius.circular(35),
          boxShadow: active && !pending
              ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5)]
              : [],
        ),
        child: Center(
          child: pending
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: active ? Colors.white : Colors.grey,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildBasicSettingsPage() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              _buildCardHeader(
                title: '⏱️ 快捷倒计时',
                subtitle: '设定时间后自动开/关插座',
                enabled: _timerEnabled,
                expanded: _timerExpanded,
                onToggleExpanded: () => setState(() => _timerExpanded = !_timerExpanded),
                onToggleEnabled: (val) {
                  setState(() {
                    _timerEnabled = val;
                    if (!val) {
                      _countdownTimer?.cancel();
                      _timerEndAt = null;
                      _remainingSeconds = 0;
                    }
                  });
                  _saveBasicSettings();
                },
              ),
              if (_timerExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Opacity(
                    opacity: _timerEnabled ? 1.0 : 0.5,
                    child: _remainingSeconds > 0 ? _buildCountdownRunning() : _buildTimerSetup(),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Column(
            children: [
              _buildCardHeader(
                title: '电量自动保护',
                subtitle: '自动维持手机电量在设定区间内',
                enabled: _autoBattery,
                expanded: _batteryExpanded,
                onToggleExpanded: () => setState(() => _batteryExpanded = !_batteryExpanded),
                onToggleEnabled: (val) {
                  setState(() => _autoBattery = val);
                  _saveBasicSettings();
                },
              ),
              if (_batteryExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Opacity(
                    opacity: _autoBattery ? 1.0 : 0.5,
                    child: Column(
                      children: [
                        _buildBatteryCondition(
                          label: '开启插座条件',
                          value: _batteryMin,
                          op: _batteryOnOp,
                          color: Colors.green,
                          onValueChanged: _setBatteryMin,
                          onOpChanged: (v) {
                            setState(() => _batteryOnOp = v);
                            _saveBasicSettings();
                          },
                          onTapValue: () async {
                            final val = await _showNumberInputDialog('低于多少时开启？', _batteryMin, '%', 100);
                            if (val != null) {
                              _setBatteryMin(val);
                              _saveBasicSettings();
                            }
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildBatteryCondition(
                          label: '关闭插座条件',
                          value: _batteryMax,
                          op: _batteryOffOp,
                          color: Colors.red,
                          onValueChanged: _setBatteryMax,
                          onOpChanged: (v) {
                            setState(() => _batteryOffOp = v);
                            _saveBasicSettings();
                          },
                          onTapValue: () async {
                            final val = await _showNumberInputDialog('高于多少时关闭？', _batteryMax, '%', 100);
                            if (val != null) {
                              _setBatteryMax(val);
                              _saveBasicSettings();
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Column(
            children: [
              _buildCardHeader(
                title: '🎵 提示音设置',
                subtitle: '触发阈值或倒计时结束时播放',
                enabled: _audioEnabled,
                expanded: _audioExpanded,
                onToggleExpanded: () => setState(() => _audioExpanded = !_audioExpanded),
                onToggleEnabled: (val) {
                  setState(() => _audioEnabled = val);
                  _saveBasicSettings();
                },
              ),
              if (_audioExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Opacity(
                    opacity: _audioEnabled ? 1.0 : 0.5,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AudioService.customAudioPath == null
                              ? '当前状态：使用内置默认提示音'
                              : '当前状态：${AudioService.customAudioName ?? "自定义音频"}',
                          style: TextStyle(
                            color: AudioService.customAudioPath == null ? Colors.grey : Colors.blue,
                            fontWeight: AudioService.customAudioPath == null ? FontWeight.normal : FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            OutlinedButton.icon(icon: const Icon(Icons.folder_open), label: const Text('选择音频'), onPressed: _pickAudio),
                            OutlinedButton.icon(icon: const Icon(Icons.volume_up), label: const Text('测试'), onPressed: () {
                              AudioService.playAlert();
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在播放...')));
                            }),
                            if (AudioService.customAudioPath != null)
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: '恢复默认', onPressed: _clearAudio),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('🔔 通知提示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 2),
                          Text('屏幕横幅 + 系统通知栏（静音+震动）', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                    Switch(
                      value: _notifyEnabled,
                      onChanged: (val) {
                        setState(() => _notifyEnabled = val);
                        _saveBasicSettings();
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('测试通知'),
                      onPressed: () {
                        NotificationService.show(
                          '智能插座测试',
                          '这是一条测试通知，如看到横幅并有震动则一切正常',
                        );
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('已发送测试通知（若没看到，请检查通知权限）'),
                        ));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_notifyEnabled)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '⚠️ 如果收不到通知，请前往手机「系统设置 -> 应用 -> 涂鸦智能插座控制 -> 通知」中允许通知。',
                      style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                    ),
                  ),
                Text(
                  _audioEnabled
                      ? '💡 提示音已开启：触发时播放你的音频 + 通知震动（无重复声音）'
                      : '💡 提示音已关闭：触发时只有通知震动，无声音',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardHeader({
    required String title,
    required String subtitle,
    required bool enabled,
    required bool expanded,
    required VoidCallback onToggleExpanded,
    required ValueChanged<bool> onToggleEnabled,
  }) {
    return ListTile(
      title: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
            tooltip: expanded ? '收起' : '展开',
            onPressed: onToggleExpanded,
          ),
          Switch(value: enabled, onChanged: onToggleEnabled),
        ],
      ),
    );
  }

  void _setBatteryMin(int v) {
    setState(() {
      _batteryMin = v.clamp(0, 99);
      if (_batteryMin >= _batteryMax) {
        _batteryMax = (_batteryMin + 1).clamp(1, 100);
      }
    });
  }

  void _setBatteryMax(int v) {
    setState(() {
      _batteryMax = v.clamp(1, 100);
      if (_batteryMax <= _batteryMin) {
        _batteryMin = (_batteryMax - 1).clamp(0, 99);
      }
    });
  }

  Widget _buildBatteryCondition({
    required String label,
    required int value,
    required String op,
    required Color color,
    required ValueChanged<int> onValueChanged,
    required ValueChanged<String> onOpChanged,
    required VoidCallback onTapValue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Row(
          children: [
            const Text('电量 ', style: TextStyle(fontSize: 15)),
            _buildOperatorDropdown(value: op, color: color, onChanged: onOpChanged),
            const SizedBox(width: 8),
            InkWell(
              onTap: onTapValue,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('$value%', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(width: 4),
                    Icon(Icons.edit, size: 14, color: color.withOpacity(0.7)),
                  ],
                ),
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: color,
            thumbColor: color,
            inactiveTrackColor: color.withOpacity(0.2),
            overlayColor: color.withOpacity(0.15),
            trackHeight: 4,
          ),
          child: Slider(
            value: value.toDouble().clamp(0, 100),
            min: 0,
            max: 100,
            divisions: 100,
            label: '$value%',
            onChanged: (v) => onValueChanged(v.round()),
            onChangeEnd: (_) => _saveBasicSettings(),
          ),
        ),
      ],
    );
  }

  Widget _buildOperatorDropdown({
    required String value,
    required Color color,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          icon: Icon(Icons.arrow_drop_down, color: color, size: 20),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          dropdownColor: Colors.white,
          items: _opOptions
              .map((op) => DropdownMenuItem(
                    value: op,
                    child: Text(_opLabel(op)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v != null && v != value) onChanged(v);
          },
        ),
      ),
    );
  }

  Widget _buildTimerSetup() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('设定时间：', style: TextStyle(fontSize: 16)),
            InkWell(
              onTap: () async {
                final val = await _showNumberInputDialog('输入分钟数', _timerMinutes, '分钟', 999, minValue: 1);
                if (val != null && val > 0) setState(() => _timerMinutes = val);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8)),
                child: Text('$_timerMinutes 分钟', style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold, fontSize: 18)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ChoiceChip(
              label: const Text('开启插座'),
              selected: _timerAction == '开启插座',
              onSelected: (val) => setState(() => _timerAction = '开启插座'),
            ),
            ChoiceChip(
              label: const Text('关闭插座'),
              selected: _timerAction == '关闭插座',
              onSelected: (val) => setState(() => _timerAction = '关闭插座'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size(200, 50), backgroundColor: Colors.blue),
          onPressed: _startTimer,
          child: const Text('开始倒计时', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }

  Widget _buildCountdownRunning() {
    return Column(
      children: [
        Text('${_remainingSeconds ~/ 60} 分 ${_remainingSeconds % 60} 秒后 $_timerAction',
            style: const TextStyle(fontSize: 20, color: Colors.blue, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red[50], foregroundColor: Colors.red),
          icon: const Icon(Icons.cancel),
          label: const Text('取消倒计时'),
          onPressed: _cancelTimer,
        ),
      ],
    );
  }

  Future<int?> _showNumberInputDialog(String title, int initialValue, String suffix, int maxValue, {int minValue = 0}) async {
    final controller = TextEditingController(text: initialValue.toString());
    return showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(suffixText: suffix, border: const OutlineInputBorder()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              if (val == null) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('请输入有效的数字'), duration: Duration(seconds: 1)),
                );
                return;
              }
              if (val < minValue || val > maxValue) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('数值必须在 $minValue 到 $maxValue 之间'), duration: const Duration(seconds: 2)),
                );
                return;
              }
              Navigator.pop(ctx, val);
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return RepaintBoundary(child: widget.child);
  }
}