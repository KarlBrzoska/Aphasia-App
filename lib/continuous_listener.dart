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


//THIS USES WHISPER
// // continuous_listener.dart
// import 'dart:async';
// import 'dart:convert';
// import 'dart:io';
// import 'dart:math';
// import 'dart:typed_data';

// import 'package:http/http.dart' as http;
// import 'package:http_parser/http_parser.dart';
// import 'package:path_provider/path_provider.dart';
// import 'package:record/record.dart';

// /* --------------------------------------------------------------------------
//  *  STEP 2 — Real mic listener + real STT (Whisper) + fake suggestions
//  * -------------------------------------------------------------------------- */

// /// ---------- Interfaces ----------
// abstract class SttEngine {
//   Future<String> transcribeBytes(Uint8List wavOrPcm16, {int sampleRate = 16000});
// }

// abstract class SuggestionEngine {
//   Future<List<String>> suggest({
//     required String transcript,
//     required Map<String, dynamic> patientProfile,
//     required List<String> recentWords,
//   });
// }

// /// ---------- Real STT (OpenAI Whisper) ----------
// class WhisperStt implements SttEngine {
//   WhisperStt({
//     required this.apiKey,
//     this.model = 'whisper-1', // if you have access, 'gpt-4o-mini-transcribe' is also great
//     this.language,            // e.g. 'en'
//     this.timeout = const Duration(seconds: 25),
//   });

//   final String apiKey;
//   final String model;
//   final String? language;
//   final Duration timeout;

//   /// We send each segment as a WAV file to OpenAI's /audio/transcriptions.
//   /// Input from the VAD is raw PCM16, so we wrap it into WAV.
//   @override
//   Future<String> transcribeBytes(Uint8List wavOrPcm16, {int sampleRate = 16000}) async {
//     // Our VAD passes raw PCM16. Wrap it into a valid WAV:
//     final wavBytes = _pcm16ToWav(wavOrPcm16, sampleRate: sampleRate, numChannels: 1);

//     // Write to a temp file for multipart
//     final dir = await getTemporaryDirectory();
//     final f = File('${dir.path}/seg_${DateTime.now().microsecondsSinceEpoch}.wav');
//     await f.writeAsBytes(wavBytes, flush: true);

//     final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
//     final req = http.MultipartRequest('POST', uri)
//       ..headers['Authorization'] = 'Bearer $apiKey'
//       ..fields['model'] = model
//       ..fields['response_format'] = 'text';
//     if (language != null) req.fields['language'] = language!;

//     req.files.add(await http.MultipartFile.fromPath(
//       'file',
//       f.path,
//       filename: 'segment.wav',
//       contentType: MediaType('audio', 'wav'),
//     ));

//     final client = http.Client();
//     try {
//       final streamed = await client.send(req).timeout(timeout);
//       final res = await http.Response.fromStream(streamed);
//       if (res.statusCode >= 200 && res.statusCode < 300) {
//         return res.body.trim();
//       } else {
//         // best-effort error surfacing
//         String detail = res.body;
//         try {
//           final j = json.decode(res.body);
//           detail = j['error']?['message']?.toString() ?? res.body;
//         } catch (_) {}
//         print('Whisper error ${res.statusCode}: $detail');
//         return '';
//       }
//     } finally {
//       client.close();
//       unawaited(Future(() async {
//         if (await f.exists()) await f.delete();
//       }));
//     }
//   }
// }

// /// Adds a minimal WAV header for 16-bit PCM, little-endian.
// Uint8List _pcm16ToWav(Uint8List pcm, {required int sampleRate, int numChannels = 1}) {
//   final byteRate = sampleRate * numChannels * 2; // 16-bit
//   final blockAlign = numChannels * 2;
//   final dataSize = pcm.lengthInBytes;
//   final totalSize = 36 + dataSize;

//   final header = BytesBuilder();
//   void _writeStr(String s) => header.add(utf8.encode(s));
//   void _write32(int v) {
//     final b = ByteData(4)..setUint32(0, v, Endian.little);
//     header.add(b.buffer.asUint8List());
//   }
//   void _write16(int v) {
//     final b = ByteData(2)..setUint16(0, v, Endian.little);
//     header.add(b.buffer.asUint8List());
//   }

//   _writeStr('RIFF');
//   _write32(totalSize);
//   _writeStr('WAVE');
//   _writeStr('fmt ');
//   _write32(16);           // PCM fmt chunk size
//   _write16(1);            // audio format = PCM
//   _write16(numChannels);  // channels
//   _write32(sampleRate);   // sample rate
//   _write32(byteRate);     // byte rate
//   _write16(blockAlign);   // block align
//   _write16(16);           // bits per sample
//   _writeStr('data');
//   _write32(dataSize);

//   final out = BytesBuilder();
//   out.add(header.toBytes());
//   out.add(pcm);
//   return out.toBytes();
// }

// /// allow fire-and-forget without analyzer warnings
// void unawaited(Future<void> f) {}

// /// ---------- Simple fake suggestions (keep for now) ----------
// class FakeSuggestionEngine implements SuggestionEngine {
//   @override
//   Future<List<String>> suggest({
//     required String transcript,
//     required Map<String, dynamic> patientProfile,
//     required List<String> recentWords,
//   }) async {
//     final lower = transcript.toLowerCase();
//     final guesses = <String>[];

//     if (lower.contains('water')) guesses.add('Water please');
//     if (lower.contains('help')) guesses.add('I need help');
//     if (lower.contains('bath')) guesses.add('I need the bathroom');
//     if (guesses.isEmpty) guesses.addAll(['Yes', 'No', 'Please repeat']);

//     return guesses.take(3).toList();
//   }
// }

// /// ---------- VAD (unchanged) ----------
// class SimpleVadSegmenter {
//   SimpleVadSegmenter({
//     this.sampleRate = 16000,
//     this.frameMs = 20,
//     this.silenceHangMs = 400,
//     this.minSegMs = 200,
//     this.maxSegMs = 8000,
//     this.rmsThreshold = 0.006,
//   });

//   final int sampleRate, frameMs, silenceHangMs, minSegMs, maxSegMs;
//   final double rmsThreshold;

//   final List<int> _buf = [];
//   bool _inSpeech = false;
//   int _segStartMs = 0, _lastSpeechMs = 0, _elapsedMs = 0;

//   Uint8List? pushFrame(Int16List pcm16) {
//     _elapsedMs += frameMs;
//     final rms = _rms(pcm16);
//     final now = _elapsedMs;

//     if (rms > rmsThreshold) {
//       if (!_inSpeech) {
//         _inSpeech = true;
//         _segStartMs = now;
//         _buf.clear();
//       }
//       _lastSpeechMs = now;
//       _buf.addAll(pcm16);
//       if (now - _segStartMs >= maxSegMs) return _flush();
//       return null;
//     } else if (_inSpeech) {
//       if (now - _lastSpeechMs < silenceHangMs) {
//         _buf.addAll(pcm16);
//         if (now - _segStartMs >= maxSegMs) return _flush();
//         return null;
//       } else {
//         if (now - _segStartMs >= minSegMs) return _flush();
//         _inSpeech = false;
//         _buf.clear();
//       }
//     }
//     return null;
//   }

//   Uint8List _flush() {
//     _inSpeech = false;
//     final data = Int16List.fromList(List<int>.from(_buf));
//     _buf.clear();
//     return Uint8List.view(data.buffer);
//   }

//   double _rms(Int16List s) {
//     if (s.isEmpty) return 0;
//     double acc = 0;
//     for (final v in s) {
//       final d = v / 32768.0;
//       acc += d * d;
//     }
//     return sqrt(acc / s.length);
//   }
// }

// /// ---------- Continuous Listener (align fix kept) ----------
// class ContinuousListener {
//   ContinuousListener({
//     required this.stt,
//     required this.suggester,
//     required this.onSuggestions,
//     required this.patientProfile,
//     this.sampleRate = 16000,
//   });

//   final SttEngine stt;
//   final SuggestionEngine suggester;
//   final void Function({
//     required String transcript,
//     required List<String> options,
//   }) onSuggestions;
//   final Map<String, dynamic> patientProfile;
//   final int sampleRate;

//   final _rec = AudioRecorder();
//   StreamSubscription<Uint8List>? _sub;
//   final _seg = SimpleVadSegmenter();
//   bool _running = false;
//   Uint8List? _carryByte; // fixes unaligned byte buffer

//   Future<bool> start() async {
//     if (_running) return true;
//     if (!await _rec.hasPermission()) return false;

//     final cfg = RecordConfig(
//       encoder: AudioEncoder.pcm16bits,
//       sampleRate: sampleRate,
//       numChannels: 1,
//       bitRate: sampleRate * 16,
//     );

//     final stream = await _rec.startStream(cfg);
//     _running = true;

//     _sub = stream.listen((bytes) async {
//       try {
//         if (bytes.isEmpty) return;

//         // ensure alignment to 16-bit samples
//         Uint8List chunk;
//         if (_carryByte != null) {
//           chunk = Uint8List(_carryByte!.length + bytes.lengthInBytes)
//             ..setAll(0, _carryByte!)
//             ..setAll(_carryByte!.length, bytes);
//           _carryByte = null;
//         } else {
//           chunk = Uint8List.fromList(bytes);
//         }

//         if (chunk.lengthInBytes.isOdd) {
//           _carryByte = Uint8List.fromList([chunk.last]);
//           chunk = chunk.sublist(0, chunk.lengthInBytes - 1);
//         }
//         if (chunk.isEmpty) return;

//         final pcm16 = Int16List.view(chunk.buffer, 0, chunk.lengthInBytes >> 1);
//         final seg = _seg.pushFrame(pcm16);

//         if (seg != null) {
//           final transcript = await stt.transcribeBytes(seg, sampleRate: sampleRate);
//           if (transcript.trim().isEmpty) return;

//           final opts = await suggester.suggest(
//             transcript: transcript,
//             patientProfile: patientProfile,
//             recentWords: const [],
//           );
//           onSuggestions(transcript: transcript, options: opts);
//         }
//       } catch (e, st) {
//         print('Audio stream error: $e\n$st');
//       }
//     });

//     return true;
//   }

//   Future<void> stop() async {
//     if (!_running) return;
//     await _sub?.cancel();
//     _sub = null;
//     await _rec.stop();
//     _carryByte = null;
//     _running = false;
//   }

//   bool get isRunning => _running;
// }
