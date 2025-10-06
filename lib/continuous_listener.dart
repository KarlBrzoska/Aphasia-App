import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:record/record.dart';

/* --------------------------------------------------------------------------
 *  STEP 1  —  Real mic listener + simple fake STT + fake suggestions
 * -------------------------------------------------------------------------- */

/// ---------- Interfaces ----------
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

/// ---------- Fake engines (demo only) ----------
class FakeStt implements SttEngine {
  int _i = 0;
  final _alts = [
    'water please',
    'help me',
    'bathroom',
    'call caregiver',
    'I feel dizzy'
  ];

  @override
  Future<String> transcribeBytes(Uint8List _, {int sampleRate = 16000}) async {
    await Future.delayed(const Duration(milliseconds: 200));
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
    final lower = transcript.toLowerCase();
    final guesses = <String>[];

    if (lower.contains('water')) guesses.add('Water please');
    if (lower.contains('help')) guesses.add('I need help');
    if (lower.contains('bath')) guesses.add('I need the bathroom');
    if (guesses.isEmpty) guesses.addAll(['Yes', 'No', 'Please repeat']);

    return guesses.take(3).toList();
  }
}

/// ---------- Simple Voice Activity Detector ----------
class SimpleVadSegmenter {
  SimpleVadSegmenter({
    this.sampleRate = 16000,
    this.frameMs = 20,
    this.silenceHangMs = 400,
    this.minSegMs = 200,
    this.maxSegMs = 8000,
    this.rmsThreshold = 0.006,
  });

  final int sampleRate, frameMs, silenceHangMs, minSegMs, maxSegMs;
  final double rmsThreshold;

  final List<int> _buf = [];
  bool _inSpeech = false;
  int _segStartMs = 0, _lastSpeechMs = 0, _elapsedMs = 0;

  Uint8List? pushFrame(Int16List pcm16) {
    _elapsedMs += frameMs;
    final rms = _rms(pcm16);
    final now = _elapsedMs;

    if (rms > rmsThreshold) {
      if (!_inSpeech) {
        _inSpeech = true;
        _segStartMs = now;
        _buf.clear();
      }
      _lastSpeechMs = now;
      _buf.addAll(pcm16);
      if (now - _segStartMs >= maxSegMs) return _flush();
      return null;
    } else if (_inSpeech) {
      if (now - _lastSpeechMs < silenceHangMs) {
        _buf.addAll(pcm16);
        if (now - _segStartMs >= maxSegMs) return _flush();
        return null;
      } else {
        if (now - _segStartMs >= minSegMs) return _flush();
        _inSpeech = false;
        _buf.clear();
      }
    }
    return null;
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
    for (final v in s) {
      final d = v / 32768.0;
      acc += d * d;
    }
    return sqrt(acc / s.length);
  }
}

/// ---------- Continuous Listener ----------
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
  final void Function({
    required String transcript,
    required List<String> options,
  }) onSuggestions;
  final Map<String, dynamic> patientProfile;
  final int sampleRate;

  final _rec = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  final _seg = SimpleVadSegmenter();
  bool _running = false;
  Uint8List? _carryByte; // fixes unaligned byte buffer

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

    _sub = stream.listen((bytes) async {
      try {
        if (bytes.isEmpty) return;

        // ensure alignment to 16-bit samples
        Uint8List chunk;
        if (_carryByte != null) {
          chunk = Uint8List(_carryByte!.length + bytes.lengthInBytes)
            ..setAll(0, _carryByte!)
            ..setAll(_carryByte!.length, bytes);
          _carryByte = null;
        } else {
          chunk = Uint8List.fromList(bytes);
        }

        if (chunk.lengthInBytes.isOdd) {
          _carryByte = Uint8List.fromList([chunk.last]);
          chunk = chunk.sublist(0, chunk.lengthInBytes - 1);
        }
        if (chunk.isEmpty) return;

        final pcm16 = Int16List.view(chunk.buffer, 0, chunk.lengthInBytes >> 1);
        final seg = _seg.pushFrame(pcm16);

        if (seg != null) {
          final transcript = await stt.transcribeBytes(seg);
          if (transcript.trim().isEmpty) return;

          final opts = await suggester.suggest(
            transcript: transcript,
            patientProfile: patientProfile,
            recentWords: const [],
          );
          onSuggestions(transcript: transcript, options: opts);
        }
      } catch (e, st) {
        print('Audio stream error: $e\n$st');
      }
    });

    return true;
  }

  Future<void> stop() async {
    if (!_running) return;
    await _sub?.cancel();
    _sub = null;
    await _rec.stop();
    _carryByte = null;
    _running = false;
  }

  bool get isRunning => _running;
}
