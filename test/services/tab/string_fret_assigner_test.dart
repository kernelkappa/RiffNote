import 'package:flutter_test/flutter_test.dart';
import 'package:riffnote/models/instrument.dart';
import 'package:riffnote/services/basic_pitch/note_decoder.dart';
import 'package:riffnote/services/tab/chord_event.dart';
import 'package:riffnote/services/tab/string_fret_assigner.dart';

DetectedNote _note(double start, int midi, {double duration = 0.3}) {
  return DetectedNote(
    startTimeSec: start,
    endTimeSec: start + duration,
    midiPitch: midi,
    amplitude: 0.8,
  );
}

void main() {
  group('groupIntoChordEvents', () {
    test('keeps far-apart notes in separate events', () {
      final notes = [_note(0.0, 40), _note(0.5, 45)];
      final events = groupIntoChordEvents(notes);
      expect(events, hasLength(2));
      expect(events[0].notes.single.midiPitch, 40);
      expect(events[1].notes.single.midiPitch, 45);
    });

    test('groups near-simultaneous onsets into one event', () {
      final notes = [_note(1.0, 40), _note(1.02, 50), _note(1.04, 55)];
      final events = groupIntoChordEvents(notes);
      expect(events, hasLength(1));
      expect(events.single.midiPitches, [40, 50, 55]);
    });

    test('sorts notes by onset regardless of input order', () {
      final notes = [_note(2.0, 64), _note(0.0, 40)];
      final events = groupIntoChordEvents(notes);
      expect(events.map((e) => e.startTimeSec), [0.0, 2.0]);
    });
  });

  group('StringFretAssigner (guitar)', () {
    final tuning = StringTuning.guitarStandard; // E2 A2 D3 G3 B3 E4

    test('places an open string note at fret 0 on the matching string', () {
      // E4 = 64, open on the 1st string (index 5).
      final events = groupIntoChordEvents([_note(0.0, 64)]);
      StringFretAssigner(tuning).assign(events);

      final pos = events.single.playedNotes.single.position!;
      expect(pos.stringIndex, 5);
      expect(pos.fret, 0);
    });

    test('prefers the lowest fret for an isolated note', () {
      // C4 = 60. Reachable on string 4 (B3) fret 1 among others; the
      // assigner should prefer the lowest available fret when nothing
      // else constrains the choice.
      final events = groupIntoChordEvents([_note(0.0, 60)]);
      StringFretAssigner(tuning).assign(events);

      final pos = events.single.playedNotes.single.position!;
      expect(pos.fret, 1);
      expect(pos.stringIndex, 4);
    });

    test('assigns simultaneous notes to distinct strings', () {
      // A chord of three notes that could physically collide if the
      // assigner didn't enforce one-note-per-string.
      final events = groupIntoChordEvents([
        _note(0.0, 40), // E2, open on string 0
        _note(0.0, 45), // A2, open on string 1
        _note(0.0, 50), // D3, open on string 2
      ]);
      StringFretAssigner(tuning).assign(events);

      final positions = events.single.playedNotes.map((n) => n.position!).toList();
      final usedStrings = positions.map((p) => p.stringIndex).toSet();
      expect(usedStrings, hasLength(3), reason: 'no two notes should share a string');
    });

    test('marks a note outside the instrument range as unplayable', () {
      // MIDI 20 is below the open low E (40) on every string.
      final events = groupIntoChordEvents([_note(0.0, 20)]);
      StringFretAssigner(tuning).assign(events);

      expect(events.single.playedNotes.single.position, isNull);
    });

    test('prefers a stable hand position across consecutive notes', () {
      // Two Cs in a row (MIDI 60): the second should reuse the same
      // string/fret as the first rather than jumping to an equally valid
      // but more distant option, since nothing else should move the hand.
      final events = groupIntoChordEvents([
        _note(0.0, 60, duration: 0.2),
        _note(0.3, 60, duration: 0.2),
      ]);
      StringFretAssigner(tuning).assign(events);

      final first = events[0].playedNotes.single.position!;
      final second = events[1].playedNotes.single.position!;
      expect(second.stringIndex, first.stringIndex);
      expect(second.fret, first.fret);
    });
  });

  group('StringTuning.forInstrument', () {
    test('returns null for voice and winds', () {
      expect(StringTuning.forInstrument(Instrument.voice), isNull);
      expect(StringTuning.forInstrument(Instrument.winds), isNull);
    });

    test('returns the right string count for guitar and bass', () {
      expect(StringTuning.forInstrument(Instrument.guitar)!.stringCount, 6);
      expect(StringTuning.forInstrument(Instrument.bass)!.stringCount, 4);
    });
  });
}
