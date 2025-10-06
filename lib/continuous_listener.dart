// continuous_listener.dart
import 'dart:async';
import 'package:speech_to_text/speech_to_text.dart' as stt;

/* --------------------------------------------------------------------------
 *  speech_to_text version — continuous live STT + your existing suggester
 * -------------------------------------------------------------------------- */

abstract class SuggestionEngine {
  Future<List<String>> suggest({
    required String transcript,
    required Map<String, dynamic> patientProfile,
    required List<String> recentWords,
  });
}

class FakeSuggestionEngine implements SuggestionEngine {
  @override
  Future<List<String>> suggest({
    required String transcript,
    required Map<String, dynamic> patientProfile,
    required List<String> recentWords,
  }) async {
    final t = transcript.toLowerCase();
    final out = <String>[];
    if (t.contains('water')) out.add('Water please');
    if (t.contains('help')) out.add('I need help');
    if (t.contains('bath')) out.add('I need the bathroom');
    if (out.isEmpty) out.addAll(['Yes', 'No', 'Please repeat']);
    return out.take(3).toList();
  }
}

/// Keeps the same public API (start/stop/isRunning + onSuggestions callback)
/// but now reacts *continuously* (not only when you press Stop)
class ContinuousListener {
  ContinuousListener({
    required this.suggester,
    required this.onSuggestions,
    required this.patientProfile,
    this.partialResults = true,
  });

  final SuggestionEngine suggester;
  final void Function({
    required String transcript,
    required List<String> options,
  }) onSuggestions;
  final Map<String, dynamic> patientProfile;
  final bool partialResults;

  final stt.SpeechToText _stt = stt.SpeechToText();
  bool _initialized = false;
  bool _running = false;
  Timer? _restartTimer; // for optional auto-restart

  Future<bool> _ensureInit() async {
    if (_initialized) return true;
    try {
      _initialized = await _stt.initialize(
        onStatus: (s) {
          _debug('status: $s');
          // Auto-restart if the engine stops listening unexpectedly
          if (s == 'notListening' && _running) {
            _restartTimer?.cancel();
            _restartTimer = Timer(const Duration(seconds: 1), () {
              if (_running) start();
            });
          }
        },
        onError: (e) => _debug('error: $e'),
      );
    } catch (e) {
      _debug('initialize exception: $e');
      _initialized = false;
    }
    return _initialized;
  }

  Future<bool> start() async {
    if (_running) return true;
    if (!await _ensureInit()) return false;

    _stt.listen(
      onResult: (result) async {
        final text = result.recognizedWords.trim();
        if (text.isEmpty) return;

        // React continuously to both partial and final results
        final options = await suggester.suggest(
          transcript: text,
          patientProfile: patientProfile,
          recentWords: const [],
        );
        onSuggestions(transcript: text, options: options);
      },
      listenMode: stt.ListenMode.dictation,
      cancelOnError: true,
      partialResults: true, // ensures continuous updates
    );

    _running = true;
    return true;
  }

  Future<void> stop() async {
    _restartTimer?.cancel();
    if (!_running) return;
    await _stt.stop();
    _running = false;
  }

  bool get isRunning => _running;

  void dispose() {
    _restartTimer?.cancel();
    _stt.stop();
  }

  void _debug(Object o) {
    // ignore: avoid_print
    print('STT: $o');
  }
}


