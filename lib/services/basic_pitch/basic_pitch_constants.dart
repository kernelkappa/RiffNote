/// Constants mirroring `basic_pitch/constants.py` and the verified shapes of
/// the bundled `assets/models/basic_pitch_nmp.tflite` model (Spotify's
/// "ICASSP 2022" Basic Pitch, Apache 2.0).
///
/// These are not guesses: input/output tensor shapes and signature mapping
/// were confirmed by parsing the .tflite flatbuffer directly (see the
/// project's development notes). Getting any of these wrong would silently
/// corrupt the transcription, so keep this file in lockstep with the model.
library;

import 'dart:math' as math;

const int semitonesPerOctave = 12;

const int fftHop = 256;

const int notesBinsPerSemitone = 1;
const int contoursBinsPerSemitone = 3;

/// Base frequency of the central bin of the first semitone (A0, lowest
/// piano key).
const double annotationsBaseFrequency = 27.5;
const int annotationsNSemitones = 88;

const int audioSampleRate = 22050;
const int audioNChannels = 1;

const int nFreqBinsNotes = annotationsNSemitones * notesBinsPerSemitone; // 88
const int nFreqBinsContours =
    annotationsNSemitones * contoursBinsPerSemitone; // 264

const int audioWindowLengthSeconds = 2;

/// 22050 / 256 = 86 (integer division, matches Python's `//`).
const int annotationsFps = audioSampleRate ~/ fftHop;

/// Number of frames in the time-frequency representation per window: 172.
const int annotNFrames = annotationsFps * audioWindowLengthSeconds;

/// Number of raw audio samples fed to the model per window: 43844.
/// Verified against the model's input tensor shape [1, 43844, 1].
const int audioNSamples = audioSampleRate * audioWindowLengthSeconds - fftHop;

/// MIDI note number of the lowest bin (A0).
const int midiOffset = 21;

const int maxFreqIdx = annotationsNSemitones - 1; // 87

/// Default decoding thresholds/parameters, from `inference.py`.
const double defaultOnsetThreshold = 0.5;
const double defaultFrameThreshold = 0.3;
const double defaultMinimumNoteLengthMs = 127.7;
const int defaultOverlappingFrames = 30;

/// Frames a note's energy is allowed to dip below threshold before the note
/// is considered to have ended (`ENERGY_TOLERANCE` in `note_creation.py`).
const int energyTolerance = 11;

/// Empirically-tuned offset used by Basic Pitch's own `model_frames_to_time`
/// to correct for windowing drift. Ported as-is from the reference
/// implementation rather than re-derived.
const double magicAlignmentOffset = 0.0018;

/// Frequency (Hz) of MIDI note bin [i] for the "note"/"onset" outputs
/// (88 bins, one per semitone starting at A0).
double noteBinFrequencyHz(int binIndex) {
  final step = math.pow(2.0, 1.0 / (semitonesPerOctave * notesBinsPerSemitone));
  return annotationsBaseFrequency * math.pow(step, binIndex);
}
