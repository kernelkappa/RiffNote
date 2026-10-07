import 'dart:typed_data';

import 'package:tflite_flutter/tflite_flutter.dart';

import 'basic_pitch_constants.dart' as c;

/// Raw model output for the whole (unwrapped) recording: one row per time
/// frame, in the same units Spotify's `basic_pitch` Python package uses
/// internally (before note decoding).
class ModelOutput {
  ModelOutput({required this.onset, required this.note, required this.contour});

  /// (nFrames x 88) onset activations.
  final List<Float64List> onset;

  /// (nFrames x 88) frame/"note" activations.
  final List<Float64List> note;

  /// (nFrames x 264) pitch-contour activations.
  final List<Float64List> contour;

  int get frameCount => note.length;
}

/// Loads the bundled Basic Pitch TFLite model and runs it over arbitrarily
/// long audio, replicating `basic_pitch.inference.run_inference`: the model
/// only accepts fixed 2-second windows, so longer recordings are split into
/// overlapping windows and the overlap is trimmed back out afterwards.
///
/// The asset path, tensor order (onset, note, contour) and all shapes here
/// were verified directly against the .tflite file, not assumed.
class BasicPitchModel {
  static const _assetPath = 'assets/models/basic_pitch_nmp.tflite';

  Interpreter? _interpreter;

  Future<void> load() async {
    _interpreter ??= await Interpreter.fromAsset(_assetPath);
  }

  void close() {
    _interpreter?.close();
    _interpreter = null;
  }

  /// Runs the model over the full recording and returns the unwrapped,
  /// de-overlapped output — ready for [note_decoder] to turn into notes.
  ModelOutput run(Float32List audio) {
    final interpreter = _interpreter;
    if (interpreter == null) {
      throw StateError('BasicPitchModel.load() must be awaited first.');
    }

    const overlappingFrames = c.defaultOverlappingFrames; // 30
    final overlapLen = overlappingFrames * c.fftHop; // 7680 samples
    final hopSize = c.audioNSamples - overlapLen; // 36164 samples

    // Pad overlapLen/2 zeros at the start, mirroring get_audio_input().
    final padded = Float32List(overlapLen ~/ 2 + audio.length);
    padded.setRange(overlapLen ~/ 2, padded.length, audio);

    final rawOnsetWindows = <List<List<double>>>[];
    final rawNoteWindows = <List<List<double>>>[];
    final rawContourWindows = <List<List<double>>>[];

    for (var i = 0; i < padded.length; i += hopSize) {
      final window = Float32List(c.audioNSamples);
      final end = (i + c.audioNSamples).clamp(0, padded.length);
      window.setRange(0, end - i, padded.sublist(i, end));

      final input = [List.generate(c.audioNSamples, (j) => [window[j]])];
      final onsetOut = _zeros3d(c.annotNFrames, c.nFreqBinsNotes);
      final noteOut = _zeros3d(c.annotNFrames, c.nFreqBinsNotes);
      final contourOut = _zeros3d(c.annotNFrames, c.nFreqBinsContours);

      // Verified tensor order: output 0 = onset, 1 = note, 2 = contour.
      interpreter.runForMultipleInputs(
        [input],
        {0: onsetOut, 1: noteOut, 2: contourOut},
      );

      rawOnsetWindows.add(onsetOut[0]);
      rawNoteWindows.add(noteOut[0]);
      rawContourWindows.add(contourOut[0]);
    }

    return ModelOutput(
      onset: _unwrap(rawOnsetWindows, audio.length, overlappingFrames, hopSize),
      note: _unwrap(rawNoteWindows, audio.length, overlappingFrames, hopSize),
      contour: _unwrap(rawContourWindows, audio.length, overlappingFrames, hopSize),
    );
  }

  static List<List<List<double>>> _zeros3d(int frames, int bins) =>
      List.generate(1, (_) => List.generate(frames, (_) => List.filled(bins, 0.0)));

  /// Port of `basic_pitch.inference.unwrap_output`: drops half the
  /// overlapping frames from each end of every window, concatenates what's
  /// left, then trims to the number of frames the original (unpadded)
  /// audio length actually accounts for.
  static List<Float64List> _unwrap(
    List<List<List<double>>> windows,
    int originalAudioLength,
    int overlappingFrames,
    int hopSize,
  ) {
    final nOlap = overlappingFrames ~/ 2; // 15
    final framesPerWindow = c.annotNFrames - overlappingFrames; // 142

    final trimmed = <Float64List>[];
    for (final window in windows) {
      for (var t = nOlap; t < window.length - nOlap; t++) {
        trimmed.add(Float64List.fromList(window[t]));
      }
    }

    final nExpectedWindows = originalAudioLength / hopSize;
    final keep = (nExpectedWindows * framesPerWindow).toInt();
    return trimmed.length <= keep ? trimmed : trimmed.sublist(0, keep);
  }
}
