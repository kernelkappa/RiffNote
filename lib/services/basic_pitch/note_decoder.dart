import 'dart:math' as math;
import 'dart:typed_data';

import 'basic_pitch_constants.dart' as c;
import 'basic_pitch_model.dart';

/// A decoded note event, in seconds and MIDI pitch — the on-device
/// equivalent of one row of Basic Pitch's `note_events` output (minus
/// pitch bends, which RiffNote doesn't need until it renders tab/notation).
class DetectedNote {
  DetectedNote({
    required this.startTimeSec,
    required this.endTimeSec,
    required this.midiPitch,
    required this.amplitude,
  });

  final double startTimeSec;
  final double endTimeSec;
  final int midiPitch;

  /// Mean frame activation over the note's duration, 0..1. Not a real
  /// velocity — same convention as upstream Basic Pitch.
  final double amplitude;

  double get durationSec => endTimeSec - startTimeSec;

  static const _noteNames = [
    'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
  ];

  /// e.g. 69 -> "A4".
  String get noteName {
    final octave = (midiPitch ~/ 12) - 1;
    final name = _noteNames[midiPitch % 12];
    return '$name$octave';
  }
}

/// Faithful Dart port of `basic_pitch.note_creation`'s polyphonic note
/// decoder. Ported function-for-function from the Python reference rather
/// than re-derived, since subtle numeric differences here would silently
/// change which notes get detected — the whole point of this module is to
/// judge Basic Pitch's own quality, not a reinterpretation of it.
///
/// Deliberately NOT ported (not needed for an on-device note list, only for
/// tab/notation rendering later): `get_pitch_bends`, MIDI file writing.
class NoteDecoder {
  const NoteDecoder({
    this.onsetThreshold = c.defaultOnsetThreshold,
    this.frameThreshold = c.defaultFrameThreshold,
    this.minimumNoteLengthMs = c.defaultMinimumNoteLengthMs,
    this.inferOnsets = true,
    this.melodiaTrick = true,
    this.minFrequencyHz,
    this.maxFrequencyHz,
    this.energyTolerance = c.energyTolerance,
  });

  final double onsetThreshold;
  final double frameThreshold;
  final double minimumNoteLengthMs;
  final bool inferOnsets;
  final bool melodiaTrick;
  final double? minFrequencyHz;
  final double? maxFrequencyHz;
  final int energyTolerance;

  List<DetectedNote> decode(ModelOutput output) {
    if (output.frameCount == 0) return const [];

    final minNoteLenFrames =
        (minimumNoteLengthMs / 1000 * c.annotationsFps).round();

    final onsets = _deepCopy(output.onset);
    final frames = _deepCopy(output.note);
    _constrainFrequency(onsets, frames, maxFrequencyHz, minFrequencyHz);

    final effectiveOnsets =
        inferOnsets ? _getInferredOnsets(onsets, frames) : onsets;

    final rawNotes = _outputToNotesPolyphonic(
      frames: frames,
      onsets: effectiveOnsets,
      onsetThresh: onsetThreshold,
      frameThresh: frameThreshold,
      minNoteLen: minNoteLenFrames,
      melodiaTrick: melodiaTrick,
      energyTol: energyTolerance,
    );

    final times = _modelFramesToTime(output.frameCount);
    final notes = rawNotes.map((n) {
      final endIdx = n.endFrame.clamp(0, times.length - 1);
      return DetectedNote(
        startTimeSec: times[n.startFrame],
        endTimeSec: times[endIdx],
        midiPitch: n.midiPitch,
        amplitude: n.amplitude,
      );
    }).toList();

    notes.sort((a, b) => a.startTimeSec.compareTo(b.startTimeSec));
    return notes;
  }

  // --- internals, one function per Python counterpart ---------------------

  static List<Float64List> _deepCopy(List<Float64List> m) =>
      m.map((row) => Float64List.fromList(row)).toList();

  /// Port of `constrain_frequency`: zeroes activations outside [minFreq, maxFreq].
  static void _constrainFrequency(
    List<Float64List> onsets,
    List<Float64List> frames,
    double? maxFreqHz,
    double? minFreqHz,
  ) {
    if (onsets.isEmpty) return;
    final nFreqs = onsets[0].length;
    var minFreqIdx = 0;
    var maxFreqIdx = nFreqs;

    if (minFreqHz != null) {
      minFreqIdx = (_hzToMidi(minFreqHz) - c.midiOffset).round();
    }
    if (maxFreqHz != null) {
      maxFreqIdx = (_hzToMidi(maxFreqHz) - c.midiOffset).round();
    }

    for (var t = 0; t < onsets.length; t++) {
      for (var f = 0; f < minFreqIdx && f < nFreqs; f++) {
        onsets[t][f] = 0;
        frames[t][f] = 0;
      }
      for (var f = maxFreqIdx; f < nFreqs; f++) {
        onsets[t][f] = 0;
        frames[t][f] = 0;
      }
    }
  }

  static double _hzToMidi(double hz) => 69 + 12 * (math.log(hz / 440) / math.ln2);

  /// Port of `get_infered_onsets`: adds onsets inferred from large
  /// frame-to-frame energy jumps, on top of the model's own onset output.
  static List<Float64List> _getInferredOnsets(
    List<Float64List> onsets,
    List<Float64List> frames, {
    int nDiff = 2,
  }) {
    final nFrames = frames.length;
    if (nFrames == 0) return onsets;
    final nFreqs = frames[0].length;

    final frameDiff = List.generate(nFrames, (_) => Float64List(nFreqs));
    for (var t = 0; t < nFrames; t++) {
      for (var f = 0; f < nFreqs; f++) {
        var minDiff = double.infinity;
        for (var n = 1; n <= nDiff; n++) {
          final prev = t >= n ? frames[t - n][f] : 0.0;
          final diff = frames[t][f] - prev;
          if (diff < minDiff) minDiff = diff;
        }
        frameDiff[t][f] = minDiff < 0 ? 0 : minDiff;
      }
    }
    for (var t = 0; t < nDiff && t < nFrames; t++) {
      frameDiff[t].fillRange(0, nFreqs, 0);
    }

    var maxOnsets = 0.0;
    for (final row in onsets) {
      for (final v in row) {
        if (v > maxOnsets) maxOnsets = v;
      }
    }
    var maxFrameDiff = 0.0;
    for (final row in frameDiff) {
      for (final v in row) {
        if (v > maxFrameDiff) maxFrameDiff = v;
      }
    }

    final result = List.generate(nFrames, (_) => Float64List(nFreqs));
    for (var t = 0; t < nFrames; t++) {
      for (var f = 0; f < nFreqs; f++) {
        final scaledDiff = maxFrameDiff > 0
            ? maxOnsets * frameDiff[t][f] / maxFrameDiff
            : 0.0;
        final onsetVal = onsets[t][f];
        result[t][f] = onsetVal > scaledDiff ? onsetVal : scaledDiff;
      }
    }
    return result;
  }

  /// Port of `output_to_notes_polyphonic`.
  static List<_RawNote> _outputToNotesPolyphonic({
    required List<Float64List> frames,
    required List<Float64List> onsets,
    required double onsetThresh,
    required double frameThresh,
    required int minNoteLen,
    required bool melodiaTrick,
    required int energyTol,
  }) {
    final nFrames = frames.length;
    if (nFrames == 0) return const [];
    final nFreqs = frames[0].length;

    // Local maxima along the time axis per frequency column (scipy's
    // argrelmax with default 'clip' mode: boundary rows are never peaks),
    // collected in matrix-scan order (time asc, then freq asc) and then
    // reversed -- this iteration order matters because later-processed
    // onsets can no longer claim energy already claimed by earlier ones.
    final candidates = <_TF>[];
    for (var t = 1; t < nFrames - 1; t++) {
      for (var f = 0; f < nFreqs; f++) {
        final v = onsets[t][f];
        if (v > onsets[t - 1][f] && v > onsets[t + 1][f] && v >= onsetThresh) {
          candidates.add(_TF(t, f));
        }
      }
    }
    final reversedCandidates = candidates.reversed.toList();

    final remainingEnergy = _deepCopy(frames);
    final notes = <_RawNote>[];

    for (final cand in reversedCandidates) {
      final noteStartIdx = cand.t;
      final freqIdx = cand.f;
      if (noteStartIdx >= nFrames - 1) continue;

      var i = noteStartIdx + 1;
      var k = 0;
      while (i < nFrames - 1 && k < energyTol) {
        if (remainingEnergy[i][freqIdx] < frameThresh) {
          k++;
        } else {
          k = 0;
        }
        i++;
      }
      i -= k;

      if (i - noteStartIdx <= minNoteLen) continue;

      for (var t = noteStartIdx; t < i; t++) {
        remainingEnergy[t][freqIdx] = 0;
        if (freqIdx < c.maxFreqIdx) remainingEnergy[t][freqIdx + 1] = 0;
        if (freqIdx > 0) remainingEnergy[t][freqIdx - 1] = 0;
      }

      var sum = 0.0;
      for (var t = noteStartIdx; t < i; t++) {
        sum += frames[t][freqIdx];
      }
      final amplitude = sum / (i - noteStartIdx);
      notes.add(_RawNote(noteStartIdx, i, freqIdx + c.midiOffset, amplitude));
    }

    if (melodiaTrick) {
      while (true) {
        var maxVal = -1.0;
        var maxT = -1;
        var maxF = -1;
        for (var t = 0; t < nFrames; t++) {
          for (var f = 0; f < nFreqs; f++) {
            final v = remainingEnergy[t][f];
            if (v > maxVal) {
              maxVal = v;
              maxT = t;
              maxF = f;
            }
          }
        }
        if (maxVal <= frameThresh) break;

        final iMid = maxT;
        final freqIdx = maxF;
        remainingEnergy[iMid][freqIdx] = 0;

        var i = iMid + 1;
        var k = 0;
        while (i < nFrames - 1 && k < energyTol) {
          if (remainingEnergy[i][freqIdx] < frameThresh) {
            k++;
          } else {
            k = 0;
          }
          remainingEnergy[i][freqIdx] = 0;
          if (freqIdx < c.maxFreqIdx) remainingEnergy[i][freqIdx + 1] = 0;
          if (freqIdx > 0) remainingEnergy[i][freqIdx - 1] = 0;
          i++;
        }
        final iEnd = i - 1 - k;

        i = iMid - 1;
        k = 0;
        while (i > 0 && k < energyTol) {
          if (remainingEnergy[i][freqIdx] < frameThresh) {
            k++;
          } else {
            k = 0;
          }
          remainingEnergy[i][freqIdx] = 0;
          if (freqIdx < c.maxFreqIdx) remainingEnergy[i][freqIdx + 1] = 0;
          if (freqIdx > 0) remainingEnergy[i][freqIdx - 1] = 0;
          i--;
        }
        final iStart = i + 1 + k;

        if (iEnd - iStart <= minNoteLen) continue;

        var sum = 0.0;
        for (var t = iStart; t < iEnd; t++) {
          sum += frames[t][freqIdx];
        }
        final amplitude = sum / (iEnd - iStart);
        notes.add(_RawNote(iStart, iEnd, freqIdx + c.midiOffset, amplitude));
      }
    }

    return notes;
  }

  /// Port of `model_frames_to_time`.
  static List<double> _modelFramesToTime(int nFrames) {
    final windowOffset = (c.fftHop / c.audioSampleRate) *
            (c.annotNFrames - (c.audioNSamples / c.fftHop)) +
        c.magicAlignmentOffset;

    return List.generate(nFrames, (n) {
      final originalTime = n * c.fftHop / c.audioSampleRate;
      final windowNumber = (n / c.annotNFrames).floor();
      return originalTime - windowOffset * windowNumber;
    });
  }
}

class _TF {
  const _TF(this.t, this.f);
  final int t;
  final int f;
}

class _RawNote {
  const _RawNote(this.startFrame, this.endFrame, this.midiPitch, this.amplitude);
  final int startFrame;
  final int endFrame;
  final int midiPitch;
  final double amplitude;
}
