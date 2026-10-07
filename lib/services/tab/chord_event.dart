import '../basic_pitch/note_decoder.dart';
import 'fretboard_position.dart';

/// One or more [DetectedNote]s that start close enough together to be
/// played as a single gesture (a chord, or just one note on its own).
///
/// Basic Pitch's output is a flat, time-ordered note list with no notion
/// of "these go together" — this is where RiffNote decides that, as a
/// prerequisite for string/fret assignment (you can't assign strings to
/// notes one at a time without knowing which ones overlap).
class ChordEvent {
  ChordEvent({required this.startTimeSec, required this.notes});

  final double startTimeSec;

  /// Original detected notes in this event, same order as [playedNotes].
  final List<DetectedNote> notes;

  /// Filled in by [StringFretAssigner]; empty until then.
  List<PlayedNote> playedNotes = const [];

  List<int> get midiPitches => notes.map((n) => n.midiPitch).toList();
}

/// Groups time-sorted notes into [ChordEvent]s: notes whose onsets fall
/// within [toleranceSec] of the group's first note are played together.
List<ChordEvent> groupIntoChordEvents(
  List<DetectedNote> notes, {
  double toleranceSec = 0.05,
}) {
  final sorted = [...notes]..sort((a, b) => a.startTimeSec.compareTo(b.startTimeSec));
  final events = <ChordEvent>[];

  for (final note in sorted) {
    if (events.isNotEmpty &&
        note.startTimeSec - events.last.startTimeSec <= toleranceSec) {
      events.last.notes.add(note);
    } else {
      events.add(ChordEvent(startTimeSec: note.startTimeSec, notes: [note]));
    }
  }
  return events;
}
