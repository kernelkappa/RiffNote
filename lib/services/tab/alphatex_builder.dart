import 'dart:math' as math;

import '../../models/instrument.dart';
import '../music/note_naming.dart';
import '../music/transposition.dart';
import 'chord_event.dart';

/// Result of converting detected notes into alphaTex source, plus enough
/// bookkeeping to be honest with the user about anything that didn't make
/// it onto the page as transcribed.
class AlphaTexBuildResult {
  const AlphaTexBuildResult({
    required this.tex,
    required this.droppedNoteCount,
    required this.outOfRangeCount,
  });

  final String tex;

  /// Notes with no playable fretboard position (guitar/bass only) —
  /// rendered as silence instead of being guessed at.
  final int droppedNoteCount;

  /// Notes outside the instrument's typical range (winds only) — still
  /// notated (it's an indicative range, not a hard physical limit like a
  /// fret position), just flagged so the user knows to double-check them.
  final int outOfRangeCount;
}

/// One beat's worth of note tokens (e.g. `"3.2"` or `"c#4"`, without the
/// trailing duration code) plus how many of the event's original notes
/// didn't make it in as a real pitch.
typedef _EventBody = ({List<String> noteTokens, int notRendered});

/// Converts [ChordEvent]s into alphaTex source for AlphaTab to render,
/// either as guitar/bass tab+notation ([buildStringed]) or as notation-only
/// for voice/winds ([buildPitched]).
///
/// Basic Pitch gives free-running timestamps in seconds, not a beat grid —
/// RiffNote doesn't do tempo/rhythm detection yet (not in the brief's MVP
/// scope), so this assumes a fixed 120 BPM and quantizes each note/rest to
/// the nearest standard duration (whole..32nd), with no triplet/tuplet
/// detection. That's a deliberate simplification for this step (wiring up
/// the renderer), not a claim of rhythmic accuracy — correcting it is
/// exactly what the future "editor di correzione" (brief section 8) is for.
class AlphaTexBuilder {
  static const _assumedBpm = 120.0;
  static const _secondsPerQuarter = 60.0 / _assumedBpm;
  static const _unitsPerBar = 4.0; // assumes 4/4

  /// alphaTex duration code -> length in quarter notes.
  static const _durationUnits = <(int code, double quarters)>[
    (1, 4.0),
    (2, 2.0),
    (4, 1.0),
    (8, 0.5),
    (16, 0.25),
    (32, 0.125),
  ];

  /// Guitar/bass: notation + tab together (`\staff{score tabs}`) — besides
  /// matching how guitarists actually read tab, this is also what gives the
  /// tab its rhythm (stems/beams on the notation staff; plain tab numbers
  /// alone carry no duration information).
  static AlphaTexBuildResult buildStringed({
    required List<ChordEvent> events,
    required StringTuning tuning,
    required String title,
  }) {
    final header = StringBuffer()
      ..writeln('\\title "${_escape(title)}"')
      ..writeln('\\tempo ${_assumedBpm.round()}')
      ..writeln('\\staff{score tabs}')
      ..writeln('\\clef ${tuning.notationClef}')
      // alphaTex lists tuning highest string first; our tuning is stored
      // low-to-high, so reverse it.
      ..writeln('\\tuning ${tuning.openStringMidi.reversed.map(midiToNoteName).join(' ')}')
      ..writeln('.');

    final result = _build(
      events: events,
      header: header.toString(),
      renderEvent: (event) {
        final playable = event.playedNotes.where((p) => p.position != null).toList();
        return (
          noteTokens: [
            for (final p in playable)
              '${p.position!.fret}.${_alphaTexString(tuning, p.position!.stringIndex)}',
          ],
          notRendered: event.notes.length - playable.length,
        );
      },
    );
    return AlphaTexBuildResult(
      tex: result.tex,
      droppedNoteCount: result.notRendered,
      outOfRangeCount: 0,
    );
  }

  /// Voice/winds: notation only, notes entered by pitch letter (`\tuning
  /// piano` switches alphaTex out of fret/string entry) and transposed from
  /// concert pitch to this instrument's written pitch (brief section 6).
  static AlphaTexBuildResult buildPitched({
    required List<ChordEvent> events,
    required Instrument instrument,
    required String title,
  }) {
    final header = StringBuffer()
      ..writeln('\\title "${_escape(title)}"')
      ..writeln('\\tempo ${_assumedBpm.round()}')
      ..writeln('\\staff{score} \\tuning piano')
      ..writeln('.');

    final result = _build(
      events: events,
      header: header.toString(),
      renderEvent: (event) {
        final transposed = event.notes.map((n) => transposeToWritten(n, instrument)).toList();
        return (
          noteTokens: [
            for (final t in transposed) midiToNoteName(t.writtenMidiPitch).toLowerCase(),
          ],
          notRendered: transposed.where((t) => !t.inRange).length,
        );
      },
    );
    return AlphaTexBuildResult(
      tex: result.tex,
      droppedNoteCount: 0,
      outOfRangeCount: result.notRendered,
    );
  }

  static ({String tex, int notRendered}) _build({
    required List<ChordEvent> events,
    required String header,
    required _EventBody Function(ChordEvent event) renderEvent,
  }) {
    final buffer = StringBuffer(header);
    var notRendered = 0;
    var barUnits = 0.0;
    double? previousEnd;

    void emit(String token, double units) {
      buffer.write('$token ');
      barUnits += units;
      if (barUnits >= _unitsPerBar - 1e-9) {
        buffer.write('| ');
        barUnits -= _unitsPerBar;
      }
    }

    for (final event in events) {
      if (previousEnd != null) {
        final gap = event.startTimeSec - previousEnd;
        if (gap > 0.05) {
          final (code, units) = _quantize(gap);
          emit('r.$code', units);
        }
      }

      final eventDuration = event.notes
          .map((n) => n.durationSec)
          .reduce((a, b) => a > b ? a : b);
      final (code, units) = _quantize(eventDuration);

      final body = renderEvent(event);
      notRendered += body.notRendered;

      if (body.noteTokens.isEmpty) {
        emit('r.$code', units);
      } else if (body.noteTokens.length == 1) {
        emit('${body.noteTokens.single}.$code', units);
      } else {
        emit('(${body.noteTokens.join(' ')}).$code', units);
      }

      previousEnd = event.notes.map((n) => n.endTimeSec).reduce((a, b) => a > b ? a : b);
    }

    return (tex: buffer.toString(), notRendered: notRendered);
  }

  /// Nearest standard duration (by ratio, i.e. comparing in log-space) for
  /// a length given in seconds at [_assumedBpm].
  static (int code, double quarters) _quantize(double seconds) {
    final quarters = seconds / _secondsPerQuarter;
    final safeQuarters = quarters <= 0 ? 0.001 : quarters;
    var best = _durationUnits.first;
    var bestDiff = double.infinity;
    for (final candidate in _durationUnits) {
      final diff = (math.log(safeQuarters) - math.log(candidate.$2)).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = candidate;
      }
    }
    return best;
  }

  static String _escape(String s) => s.replaceAll('"', "'");

  /// alphaTex's per-note string number for our `\tuning` declaration
  /// (highest string first, e.g. "E4 B3 G3 D3 A2 E2"): verified on a real
  /// rendered tab that it's a direct 1-based position in THAT declared
  /// order — i.e. the same "string 1 = highest" numbering guitarists read
  /// tab with, not our internal low-to-high [stringIndex]. An earlier
  /// version of this derived the opposite rule from alphaTab's own parser
  /// test fixtures and got it backwards (low string rendered on top); this
  /// formula is the one actually confirmed against rendered output.
  static int _alphaTexString(StringTuning tuning, int stringIndex) =>
      tuning.stringCount - stringIndex;
}
