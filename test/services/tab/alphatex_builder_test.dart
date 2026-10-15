import 'package:flutter_test/flutter_test.dart';
import 'package:riffnote/models/instrument.dart';
import 'package:riffnote/services/basic_pitch/note_decoder.dart';
import 'package:riffnote/services/tab/alphatex_builder.dart';
import 'package:riffnote/services/tab/chord_event.dart';
import 'package:riffnote/services/tab/string_fret_assigner.dart';

DetectedNote _note(double start, int midi, {double duration = 0.5}) {
  return DetectedNote(
    startTimeSec: start,
    endTimeSec: start + duration,
    midiPitch: midi,
    amplitude: 0.8,
  );
}

void main() {
  group('AlphaTexBuilder.buildStringed string numbering', () {
    // This is the easy-to-get-backwards part. An earlier version derived
    // the mapping from alphaTab's own parser test fixtures and got it
    // backwards (low string rendered at the top of the tab). This is now
    // pinned to what was actually observed in a rendered tab on a real
    // device: with the tuning declared highest-string-first (as
    // AlphaTexBuilder does), the note syntax `fret.N` uses N=1 for the
    // HIGHEST string, counting up to N=stringCount for the LOWEST — the
    // same "string 1 = highest" numbering guitarists read tab with, and
    // the same convention the app's own note list already displays
    // ("corda" = stringCount - stringIndex). Getting this backwards would
    // silently swap which string every single note lands on.
    final tuning = StringTuning.guitarStandard; // E2 A2 D3 G3 B3 E4

    test('declares a combined notation+tab staff, tuning highest string first', () {
      final events = groupIntoChordEvents([_note(0.0, 64)]); // E4, open
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('\\staff{score tabs}'));
      expect(result.tex, contains('\\tuning E4 B3 G3 D3 A2 E2'));
    });
  });

  group('AlphaTexBuilder.buildStringed clef', () {
    final tuning = StringTuning.guitarStandard;

    // Reported bug: bass transcriptions were rendering in treble clef.
    // Guitar reads in treble clef, bass in bass clef — pin both so this
    // can't silently regress.
    test('guitar uses treble clef', () {
      final tuning = StringTuning.guitarStandard;
      final events = groupIntoChordEvents([_note(0.0, 40)]);
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('\\clef treble'));
    });

    test('bass uses bass clef, not treble', () {
      final tuning = StringTuning.bassStandard;
      final events = groupIntoChordEvents([_note(0.0, 28)]);
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('\\clef bass'));
      expect(result.tex, isNot(contains('\\clef treble')));
    });

    test('open low E (string index 0) is written as string 6, not 1', () {
      final events = groupIntoChordEvents([_note(0.0, 40)]); // E2, open
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('0.6.'));
      expect(result.tex, isNot(contains('0.1.')));
    });

    test('open high E (string index 5) is written as string 1, not 6', () {
      final events = groupIntoChordEvents([_note(0.0, 64)]); // E4, open
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('0.1.'));
      expect(result.tex, isNot(contains('0.6.')));
    });
  });

  group('AlphaTexBuilder.buildStringed structure', () {
    final tuning = StringTuning.guitarStandard;

    test('renders a chord as a parenthesized group', () {
      final events = groupIntoChordEvents([
        _note(0.0, 40), // E2 open, string 6
        _note(0.0, 45), // A2 open, string 5
      ]);
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.tex, contains('(0.6 0.5).'));
    });

    test('marks an out-of-range note as dropped and emits a rest', () {
      final events = groupIntoChordEvents([_note(0.0, 20)]); // unplayable
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      expect(result.droppedNoteCount, 1);
      expect(result.outOfRangeCount, 0);
      expect(result.tex, contains('r.'));
    });

    test('inserts a rest for a silent gap between notes', () {
      final events = groupIntoChordEvents([
        _note(0.0, 40, duration: 0.2),
        _note(2.0, 45, duration: 0.2), // big gap before this one
      ]);
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(events: events, tuning: tuning, title: 't');

      // Two real notes plus at least one rest token for the gap.
      expect('r.'.allMatches(result.tex).length, greaterThanOrEqualTo(1));
    });
  });

  group('AlphaTexBuilder.buildStringed bass', () {
    test('bass tuning is declared highest string first too', () {
      final tuning = StringTuning.bassStandard; // E1 A1 D2 G2
      final events = groupIntoChordEvents([_note(0.0, 43)]); // G2, open, highest
      StringFretAssigner(tuning).assign(events);
      final result = AlphaTexBuilder.buildStringed(
        events: events,
        tuning: tuning,
        title: 't',
      );

      expect(result.tex, contains('\\tuning G2 D2 A1 E1'));
      expect(result.tex, contains('0.1.')); // highest string index(3) -> N=1
    });
  });

  group('AlphaTexBuilder.buildPitched', () {
    test('declares a notation-only, unstringed staff', () {
      final events = groupIntoChordEvents([_note(0.0, 60)]); // C4
      final result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: Instrument.voice,
        title: 't',
      );

      expect(result.tex, contains('\\staff{score} \\tuning piano'));
    });

    test('non-transposing instrument writes concert pitch as-is', () {
      final events = groupIntoChordEvents([_note(0.0, 60)]); // C4, concert
      final result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: Instrument.voice,
        title: 't',
      );

      expect(result.tex, contains('c4.'));
    });

    test('transposing instrument shifts concert pitch to written pitch', () {
      // Concert A3 (57) on a Bb clarinet (+2 semitones) is written B3 (59).
      final events = groupIntoChordEvents([_note(0.0, 57)]);
      final result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: Instrument.clarinetBb,
        title: 't',
      );

      expect(result.tex, contains('b3.'));
      expect(result.outOfRangeCount, 0);
    });

    test('renders a chord as a parenthesized group of pitches', () {
      final events = groupIntoChordEvents([_note(0.0, 60), _note(0.0, 64)]); // C4+E4
      final result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: Instrument.voice,
        title: 't',
      );

      expect(result.tex, contains('(c4 e4).'));
    });

    test('flags an out-of-range note but still renders it', () {
      // MIDI 20 is far below any wind instrument's typical range.
      final events = groupIntoChordEvents([_note(0.0, 20)]);
      final result = AlphaTexBuilder.buildPitched(
        events: events,
        instrument: Instrument.flute,
        title: 't',
      );

      expect(result.outOfRangeCount, 1);
      expect(result.droppedNoteCount, 0);
      expect(result.tex, isNot(contains('r.')), reason: 'still notated, not dropped as a rest');
    });
  });
}
