import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../theme/theme.dart';

class VoiceRecorderButton extends StatefulWidget {
  final Future<void> Function(String path, int durationMs, int listenLimit) onSend;
  const VoiceRecorderButton({super.key, required this.onSend});
  @override
  State<VoiceRecorderButton> createState() => _VoiceRecorderButtonState();
}

class _VoiceRecorderButtonState extends State<VoiceRecorderButton> {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _timer;
  DateTime? _startedAt;
  bool _recording = false;
  bool _longPress = false;
  bool _ignoreNextTap = false;
  int _elapsedMs = 0;

  Future<void> _start() async {
    if (_recording) return;
    if (!await _recorder.hasPermission()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission is required.')));
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
      autoGain: true,
      echoCancel: true,
      noiseSuppress: true,
    ), path: path);
    _startedAt = DateTime.now();
    _elapsedMs = 0;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _startedAt == null) return;
      setState(() => _elapsedMs = DateTime.now().difference(_startedAt!).inMilliseconds);
      if (_elapsedMs >= 120000) _stop();
    });
    if (mounted) setState(() => _recording = true);
  }

  Future<void> _stop() async {
    if (!_recording) return;
    _timer?.cancel();
    final path = await _recorder.stop();
    final duration = _startedAt == null ? _elapsedMs : DateTime.now().difference(_startedAt!).inMilliseconds;
    _startedAt = null;
    if (mounted) setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    if (!await file.exists() || duration < 300) {
      try { await file.delete(); } catch (_) {}
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice message is too short.')));
      return;
    }
    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => _VoicePreviewSheet(path: path, durationMs: duration),
    );
    if (result == null) {
      try { await file.delete(); } catch (_) {}
      return;
    }
    try {
      await widget.onSend(path, duration, result);
    } finally {
      await file.delete().catchError((_) {});
    }
  }

  void _onTap() {
    if (_ignoreNextTap) { _ignoreNextTap = false; return; }
    if (_recording) { _stop(); } else { _start(); }
  }

  void _onLongStart(LongPressStartDetails _) {
    _longPress = true;
    _ignoreNextTap = true;
    _start();
  }

  void _onLongEnd(LongPressEndDetails _) {
    if (_longPress) {
      _longPress = false;
      _ignoreNextTap = true;
      _stop();
      Future.delayed(const Duration(milliseconds: 350), () { if (mounted) _ignoreNextTap = false; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  String _time(int ms) {
    final seconds = (ms / 1000).floor();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _onTap,
      onLongPressStart: _onLongStart,
      onLongPressEnd: _onLongEnd,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: _recording ? 70 : 44,
        height: 44,
        decoration: BoxDecoration(
          color: _recording ? AppColors.error.withOpacity(.16) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: _recording
            ? Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.mic, color: AppColors.error, size: 20),
                const SizedBox(width: 2),
                Text(_time(_elapsedMs), style: const TextStyle(fontSize: 10, color: AppColors.error)),
              ])
            : const Icon(Icons.mic_none, size: 22),
      ),
    );
  }
}

class _VoicePreviewSheet extends StatefulWidget {
  final String path;
  final int durationMs;
  const _VoicePreviewSheet({required this.path, required this.durationMs});
  @override
  State<_VoicePreviewSheet> createState() => _VoicePreviewSheetState();
}

class _VoicePreviewSheetState extends State<_VoicePreviewSheet> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _wave;
  bool _playing = false;
  int _listenLimit = 1;
  Duration _position = Duration.zero;
  late Duration _duration;

  @override
  void initState() {
    super.initState();
    _duration = Duration(milliseconds: widget.durationMs);
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _player.onDurationChanged.listen((d) { if (mounted && d > Duration.zero) setState(() => _duration = d); });
    _player.onPlayerComplete.listen((_) {
      if (mounted) { setState(() { _playing = false; _position = _duration; }); _wave.stop(); }
    });
  }

  Future<void> _togglePlay() async {
    if (_playing) {
      await _player.pause();
      _wave.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    await _player.play(DeviceFileSource(widget.path, mimeType: 'audio/mp4'));
    _wave.repeat();
    if (mounted) setState(() => _playing = true);
  }

  @override
  void dispose() { _wave.dispose(); _player.dispose(); super.dispose(); }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _limitButton(int value) {
    final selected = _listenLimit == value;
    return OutlinedButton(
      onPressed: () => setState(() => _listenLimit = value),
      style: OutlinedButton.styleFrom(
        backgroundColor: selected ? AppColors.accentSoft : null,
        side: BorderSide(color: selected ? AppColors.accent : AppColors.border),
      ),
      child: Text('$value time${value == 1 ? '' : 's'}'),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxMs = _duration.inMilliseconds <= 0 ? widget.durationMs : _duration.inMilliseconds;
    final value = maxMs <= 0 ? 0.0 : (_position.inMilliseconds / maxMs).clamp(0.0, 1.0);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Voice message', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 18),
          Row(children: [
            IconButton(onPressed: _togglePlay, iconSize: 34, icon: Icon(_playing ? Icons.pause_circle_filled : Icons.play_circle_fill)),
            Expanded(child: Column(children: [
              SizedBox(height: 30, child: AnimatedBuilder(
                animation: _wave,
                builder: (_, __) => Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(22, (i) {
                  final pulse = 5 + 14 * ((i % 5 + _wave.value * 5) % 5) / 5;
                  return Container(width: 3, height: _playing ? pulse : 7, margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(color: AppColors.accent.withOpacity(.8), borderRadius: BorderRadius.circular(3)));
                })),
              )),
              Slider(value: value, onChanged: maxMs <= 0 ? null : (v) => _player.seek(Duration(milliseconds: (maxMs * v).round()))),
              Text('${_fmt(_position)} / ${_fmt(_duration)}', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ])),
          ]),
          const SizedBox(height: 12),
          const Align(alignment: Alignment.centerLeft, child: Text('How many times can it be heard?', style: TextStyle(fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          Row(children: [Expanded(child: _limitButton(1)), const SizedBox(width: 10), Expanded(child: _limitButton(2))]),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: OutlinedButton.icon(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.delete_outline), label: const Text('Cancel'))),
            const SizedBox(width: 10),
            Expanded(child: FilledButton.icon(onPressed: () => Navigator.pop(context, _listenLimit), icon: const Icon(Icons.send), label: const Text('Send'))),
          ]),
        ]),
      ),
    );
  }
}

class VoiceMessageBubble extends StatefulWidget {
  final String messageId;
  final bool room;
  final bool isMe;
  final int durationMs;
  final int listenCount;
  final int listenLimit;
  final DateTime? createdAt;
  const VoiceMessageBubble({super.key, required this.messageId, required this.room, required this.isMe, required this.durationMs, required this.listenCount, required this.listenLimit, this.createdAt});
  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> with SingleTickerProviderStateMixin {
  final AudioPlayer _player = AudioPlayer();
  late final AnimationController _wave;
  bool _playing = false;
  bool _loading = false;
  int _listenCount = 0;
  int _listenLimit = 1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _finalPlay = false;
  Timer? _expiryTicker;

  @override
  void initState() {
    super.initState();
    _listenCount = widget.listenCount;
    _listenLimit = widget.listenLimit <= 0 ? 1 : widget.listenLimit;
    _duration = Duration(milliseconds: widget.durationMs);
    _wave = AnimationController(vsync: this, duration: const Duration(milliseconds: 650));
    _player.onPositionChanged.listen((p) { if (mounted) setState(() => _position = p); });
    _player.onDurationChanged.listen((d) { if (mounted && d > Duration.zero) setState(() => _duration = d); });
    _player.onPlayerComplete.listen((_) => _finishPlayback());
    if (widget.createdAt != null) {
      _expiryTicker = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _finishPlayback() async {
    if (!mounted) return;
    _wave.stop();
    setState(() => _playing = false);
    if (_finalPlay) await _cleanup();
  }

  Future<void> _cleanup() async {
    try {
      await Supabase.instance.client.functions.invoke('voice-message',
        body: {'mode': 'cleanup', 'messageId': widget.messageId, 'room': widget.room});
    } catch (_) {}
  }

  bool get _expired => widget.createdAt != null && DateTime.now().isAfter(widget.createdAt!.toLocal().add(const Duration(hours: 24)));

  Future<void> _play() async {
    if (_loading || _playing || _listenCount >= _listenLimit || _expired) return;
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client.functions.invoke('voice-message',
        body: {'mode': 'play', 'messageId': widget.messageId, 'room': widget.room});
      final data = Map<String, dynamic>.from(response.data as Map);
      final url = data['url']?.toString();
      if (url == null || url.isEmpty) throw StateError('Voice URL unavailable');
      _listenCount = (data['listenCount'] as num?)?.toInt() ?? (_listenCount + 1);
      _listenLimit = (data['listenLimit'] as num?)?.toInt() ?? _listenLimit;
      _finalPlay = data['finalPlay'] == true;
      await _player.play(UrlSource(url, mimeType: 'audio/mp4'));
      _wave.repeat();
      if (mounted) setState(() { _loading = false; _playing = true; });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Voice message is no longer available.')));
      }
    }
  }

  @override
  void dispose() { _wave.dispose(); _player.dispose(); super.dispose(); }

  String _fmt(Duration d) {
    final s = d.inSeconds;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final expired = _expired;
    final disabled = expired || _listenCount >= _listenLimit;
    final maxMs = _duration.inMilliseconds;
    return Container(
      width: 230,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: widget.isMe ? AppColors.accent.withOpacity(.18) : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Row(children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          onPressed: disabled ? null : _play,
          icon: _loading ? const SizedBox(width: 22,height:22,child:CircularProgressIndicator(strokeWidth:2)) : Icon(
            disabled ? Icons.volume_off : (_playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
            color: widget.isMe ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(height: 24, child: AnimatedBuilder(
            animation: _wave,
            builder: (_, __) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: List.generate(20, (i) {
              final h = _playing
                  ? (5.0 + ((i * 7 + (_wave.value * 20)) % 16))
                  : 6.0;
              return Expanded(
                child: Container(
                  height: h,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: widget.isMe
                        ? AppColors.textOnAccent.withOpacity(.75)
                        : AppColors.accent.withOpacity(.75),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            })),
          )),
          Text(
            expired ? 'Voice expired after 24 hours' : '${_fmt(_position)} / ${_fmt(_duration)} • $_listenCount/$_listenLimit',
            style: TextStyle(
              fontSize: 10,
              color: widget.isMe ? Theme.of(context).colorScheme.onSurfaceVariant : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ])),
      ]),
    );
  }
}
