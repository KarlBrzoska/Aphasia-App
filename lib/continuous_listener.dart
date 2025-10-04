import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';

abstract class SttEngine {
  Future<String> transcribeBytes(Uint8List wavPcm16, {int sampleRate = 16000});
}

abstract class SuggestionEngine {
  Future<List<String>> suggest({
    required String transcript,
    required Map<String, dynamic> patientProfile,
    required List<String> recentWords,
  });
}

// --- Stubs ---
class FakeStt implements SttEngine {
  int _i = 0;
  final _alts = ['headache', 'water please', 'bathroom', 'i feel dizzy', 'call my caregiver'];
  @override
  Future<String> transcribeBytes(Uint8List _, {int sampleRate = 16000}) async {
    await Future.delayed(const Duration(milliseconds: 120));
    _i = (_i + 1) % _alts.length;
    return _alts[_i];
  }
}

class FakeSuggestionEngine implements SuggestionEngine {
  @override
  Future<List<String>> suggest({
    required String transcript,
    required Map<String, dynamic> patientProfile,
    required List<String> recentWords,
  }) async {
    final likes = (patientProfile['personalization']?['interests'] ?? '').toString().toLowerCase();
    final guesses = <String>[];
    if (transcript.contains('head')) guesses.add('Headache');
    if (transcript.contains('dizz')) guesses.add('I’m dizzy');
    if (likes.contains('coffee')) guesses.add('Coffee please');
    if (likes.contains('music')) guesses.add('Play music');
    if (guesses.isEmpty) guesses.addAll(['I need help', 'Water please']);
    final out = <String>{transcript, ...guesses}.where((s) => s.trim().isNotEmpty).toList();
    return out.take(3).toList();
  }
}

// --- Tuned VAD ---
class SimpleVadSegmenter {
  SimpleVadSegmenter({
    this.sampleRate = 16000,
    this.frameMs = 20,
    this.silenceHangMs = 400, // shorter hang
    this.minSegMs = 200,      // shorter minimum
    this.maxSegMs = 8000,
    this.rmsThreshold = 0.005, // more sensitive
  });

  final int sampleRate, frameMs, silenceHangMs, minSegMs, maxSegMs;
  final double rmsThreshold;
  final List<int> _buf = [];
  bool _inSpeech = false;
  int _segStartMs = 0, _lastSpeechMs = 0, _elapsedMs = 0;

  Uint8List? pushFrame(Int16List pcm16) {
    _elapsedMs += frameMs;
    final rms = _rms(pcm16);
    final nowMs = _elapsedMs;

    if (rms > rmsThreshold) {
      if (!_inSpeech) {
        _inSpeech = true;
        _segStartMs = nowMs;
        _buf.clear();
      }
      _lastSpeechMs = nowMs;
      _buf.addAll(pcm16);
      if (nowMs - _segStartMs >= maxSegMs) return _flush();
      return null;
    } else {
      if (_inSpeech) {
        if (nowMs - _lastSpeechMs < silenceHangMs) {
          _buf.addAll(pcm16);
          if (nowMs - _segStartMs >= maxSegMs) return _flush();
          return null;
        } else {
          if (nowMs - _segStartMs >= minSegMs) return _flush();
          _inSpeech = false;
          _buf.clear();
        }
      }
      return null;
    }
  }

  Uint8List _flush() {
    _inSpeech = false;
    final data = Int16List.fromList(List<int>.from(_buf));
    _buf.clear();
    return Uint8List.view(data.buffer);
  }

  double _rms(Int16List s) {
    if (s.isEmpty) return 0;
    double acc = 0;
    for (var v in s) {
      final d = v / 32768.0;
      acc += d * d;
    }
    return sqrt(acc / s.length);
  }
}

// --- Orchestrator ---
class ContinuousListener {
  ContinuousListener({
    required this.stt,
    required this.suggester,
    required this.onSuggestions,
    required this.patientProfile,
    this.sampleRate = 16000,
  });

  final SttEngine stt;
  final SuggestionEngine suggester;
  final void Function({required String transcript, required List<String> options}) onSuggestions;
  final Map<String, dynamic> patientProfile;
  final int sampleRate;

  final _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final _seg = SimpleVadSegmenter();
  bool _running = false;

  Future<bool> start() async {
    if (_running) return true;
    if (!await _rec.hasPermission()) return false;

    final cfg = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRate,
      numChannels: 1,
      bitRate: sampleRate * 16,
    );

    final stream = await _rec.startStream(cfg);
    _running = true;

    // Debug fallback → show a suggestion after 3s if nothing triggers
    Future.delayed(const Duration(seconds: 3), () {
      if (_running) {
        onSuggestions(
          transcript: '(debug) water please',
          options: const ['Water please', 'I need help', 'Call my caregiver'],
        );
      }
    });

    _sub = stream.listen((bytes) async {
      if (bytes.isEmpty) return;
      final int16 = Int16List.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);
      final seg = _seg.pushFrame(int16);
      if (seg != null) {
        final transcript = await stt.transcribeBytes(seg, sampleRate: sampleRate);
        if (transcript.trim().isEmpty) return;

        final options = await suggester.suggest(
          transcript: transcript,
          patientProfile: patientProfile,
          recentWords: const [],
        );
        onSuggestions(transcript: transcript, options: options);
      }
    });

    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await _rec.stop();
    _running = false;
  }

  bool get isRunning => _running;
}
