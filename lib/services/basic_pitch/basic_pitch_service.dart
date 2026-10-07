import 'dart:io';

import 'basic_pitch_constants.dart' as c;
import 'basic_pitch_model.dart';
import 'note_decoder.dart';
import 'wav_decoder.dart';

/// Ties together WAV decoding, the TFLite model and note decoding into a
/// single "give me notes for this recording" call.
///
/// Kept as its own service (rather than folded into the UI) so it can be
/// reused once the guitar/bass string-fret assignment and voice/winds
/// pipelines are built on top of the same note list.
class BasicPitchService {
  final BasicPitchModel _model = BasicPitchModel();
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    await _model.load();
    _loaded = true;
  }

  /// Transcribes a WAV file recorded by RiffNote (mono PCM16 @ 22050 Hz —
  /// see [HomeScreen]'s RecordConfig) into a list of detected notes.
  Future<List<DetectedNote>> transcribeFile(File wavFile) async {
    await ensureLoaded();

    final decoded = await WavDecoder.decodeFile(wavFile);
    if (decoded.sampleRate != c.audioSampleRate) {
      throw StateError(
        'Expected a ${c.audioSampleRate} Hz recording, got '
        '${decoded.sampleRate} Hz. RiffNote records at the rate Basic '
        'Pitch expects, so this file was probably not recorded by the app.',
      );
    }

    final modelOutput = _model.run(decoded.samples);
    return const NoteDecoder().decode(modelOutput);
  }

  void dispose() {
    _model.close();
    _loaded = false;
  }
}
