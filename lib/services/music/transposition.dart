import '../../models/instrument.dart';
import '../basic_pitch/note_decoder.dart';

/// A note after transposing from concert pitch to a specific instrument's
/// written pitch, with whether it fell inside that instrument's typical
/// range.
class TransposedNote {
  const TransposedNote({
    required this.source,
    required this.writtenMidiPitch,
    required this.inRange,
  });

  /// The original, untransposed (concert pitch) detected note.
  final DetectedNote source;

  final int writtenMidiPitch;

  /// False if outside [Instrument.concertRange] — flagged rather than
  /// silently rendered, same spirit as [StringFretAssigner] marking
  /// fretboard-unplayable notes.
  final bool inRange;
}

/// Basic Pitch always outputs concert pitch — it has no idea which
/// instrument was played (brief section 2: the user picks it, nothing is
/// guessed). Concert pitch stays the source of truth (brief section 6) so
/// re-transposing for a different instrument never needs re-transcribing;
/// this only computes the written-pitch view for display.
TransposedNote transposeToWritten(DetectedNote note, Instrument instrument) {
  final written = note.midiPitch + instrument.transpositionSemitones;
  final range = instrument.concertRange;
  final inRange = range == null ||
      (note.midiPitch >= range.$1 && note.midiPitch <= range.$2);
  return TransposedNote(source: note, writtenMidiPitch: written, inRange: inRange);
}
