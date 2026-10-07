import '../../models/instrument.dart';
import 'chord_event.dart';
import 'fretboard_position.dart';

/// A candidate way to play one [ChordEvent]: one fretboard position per
/// playable note, in the same order as the event's notes (`null` where a
/// note couldn't be placed at all).
class _Fingering {
  _Fingering(this.positions);

  final List<FretboardPosition?> positions;

  Iterable<FretboardPosition> get fretted =>
      positions.whereType<FretboardPosition>().where((p) => !p.isOpenString);

  /// Average fret of the non-open notes, used as a stand-in for "where the
  /// fretting hand sits" — 0 (nut/open position) if everything is open or
  /// unplayable.
  double get handPosition {
    final f = fretted.toList();
    if (f.isEmpty) return 0;
    return f.map((p) => p.fret).reduce((a, b) => a + b) / f.length;
  }

  double get span {
    final f = fretted.toList();
    if (f.length < 2) return 0;
    final frets = f.map((p) => p.fret);
    return (frets.reduce((a, b) => a > b ? a : b) -
            frets.reduce((a, b) => a < b ? a : b))
        .toDouble();
  }
}

/// Assigns each note in a sequence of [ChordEvent]s to a (string, fret)
/// position on a guitar or bass neck.
///
/// This is the "algoritmo di ottimizzazione" from the project brief
/// (section 5): a dynamic-programming search (Viterbi-style) over per-event
/// fingering candidates, minimizing hand-position jumps between
/// consecutive events and preferring compact, low-fret shapes — not a ML
/// model, just deterministic combinatorics on the tuning.
class StringFretAssigner {
  StringFretAssigner(this.tuning);

  final StringTuning tuning;

  /// Weight for jumping the hand position between consecutive events.
  static const _transitionWeight = 2.0;

  /// Weight for how spread out a chord's own fretted notes are.
  static const _spanWeight = 1.0;

  /// Small nudge towards lower (more comfortable) positions overall.
  static const _lowPositionWeight = 0.3;

  /// Caps combinatorial blow-up for dense chords; falls back to a greedy
  /// per-note assignment if a single event would exceed this many
  /// candidate fingerings.
  static const _maxCandidatesPerEvent = 200;

  void assign(List<ChordEvent> events) {
    if (events.isEmpty) return;

    final candidatesPerEvent = events.map(_candidateFingerings).toList();

    // dp[i][k] = best cumulative cost ending at candidate k of event i;
    // backpointers[i][k] = which candidate of event i-1 it came from.
    var prevCosts = <double>[];
    final backpointers = <List<int>>[];
    final chosenIndexPerEvent = List<int>.filled(events.length, 0);

    for (var i = 0; i < events.length; i++) {
      final candidates = candidatesPerEvent[i];
      final costs = List<double>.filled(candidates.length, double.infinity);
      final eventBackpointers = List<int>.filled(candidates.length, -1);

      for (var k = 0; k < candidates.length; k++) {
        final own = _ownCost(candidates[k]);
        if (i == 0) {
          costs[k] = own;
          continue;
        }
        var best = double.infinity;
        var bestPrev = 0;
        for (var j = 0; j < prevCosts.length; j++) {
          final total =
              prevCosts[j] + _transitionCost(candidatesPerEvent[i - 1][j], candidates[k]) + own;
          if (total < best) {
            best = total;
            bestPrev = j;
          }
        }
        costs[k] = best;
        eventBackpointers[k] = bestPrev;
      }

      prevCosts = costs;
      backpointers.add(eventBackpointers);
    }

    // Pick the best final candidate, then backtrack.
    var bestFinal = 0;
    for (var k = 1; k < prevCosts.length; k++) {
      if (prevCosts[k] < prevCosts[bestFinal]) bestFinal = k;
    }
    var k = bestFinal;
    for (var i = events.length - 1; i >= 0; i--) {
      chosenIndexPerEvent[i] = k;
      if (i > 0) k = backpointers[i][k];
    }

    for (var i = 0; i < events.length; i++) {
      final fingering = candidatesPerEvent[i][chosenIndexPerEvent[i]];
      events[i].playedNotes = [
        for (var n = 0; n < events[i].notes.length; n++)
          PlayedNote(
            midiPitch: events[i].notes[n].midiPitch,
            position: fingering.positions[n],
          ),
      ];
    }
  }

  double _ownCost(_Fingering f) =>
      f.span * _spanWeight + f.handPosition * _lowPositionWeight;

  double _transitionCost(_Fingering prev, _Fingering curr) =>
      (curr.handPosition - prev.handPosition).abs() * _transitionWeight;

  /// All valid (string, fret) options for a single pitch, nut to
  /// [StringTuning.maxFret], lowest fret first (open strings preferred).
  List<FretboardPosition> _optionsForPitch(int midiPitch) {
    final options = <FretboardPosition>[];
    for (var s = 0; s < tuning.stringCount; s++) {
      final fret = midiPitch - tuning.openStringMidi[s];
      if (fret >= 0 && fret <= tuning.maxFret) {
        options.add(FretboardPosition(stringIndex: s, fret: fret));
      }
    }
    return options;
  }

  /// Enumerates ways to assign every note in [event] to a distinct string.
  /// Notes with no valid position at all (out of range) get `null` and are
  /// excluded from the distinctness search. Falls back to a greedy
  /// (non-optimal but always-valid) assignment if the search space is too
  /// large for exhaustive enumeration.
  List<_Fingering> _candidateFingerings(ChordEvent event) {
    final pitches = event.midiPitches;
    final optionsPerNote = pitches.map(_optionsForPitch).toList();

    final playableIndices = [
      for (var n = 0; n < pitches.length; n++)
        if (optionsPerNote[n].isNotEmpty) n,
    ];

    final branchingProduct = playableIndices.fold<double>(
      1,
      (acc, n) => acc * optionsPerNote[n].length,
    );

    final results = <_Fingering>[];
    if (branchingProduct <= _maxCandidatesPerEvent) {
      final current = List<FretboardPosition?>.filled(pitches.length, null);
      _backtrack(playableIndices, 0, optionsPerNote, <int>{}, current, results);
    }

    if (results.isEmpty) {
      // Exhaustive search skipped (too large) or found nothing playable
      // together (e.g. more notes than strings): greedily claim the
      // lowest free fret per note, highest-amplitude/lowest-index first.
      results.add(_greedyFingering(playableIndices, optionsPerNote, pitches.length));
    }
    return results;
  }

  void _backtrack(
    List<int> playableIndices,
    int cursor,
    List<List<FretboardPosition>> optionsPerNote,
    Set<int> usedStrings,
    List<FretboardPosition?> current,
    List<_Fingering> results,
  ) {
    if (cursor == playableIndices.length) {
      results.add(_Fingering(List.of(current)));
      return;
    }
    final noteIndex = playableIndices[cursor];
    var placedAny = false;
    for (final option in optionsPerNote[noteIndex]) {
      if (usedStrings.contains(option.stringIndex)) continue;
      placedAny = true;
      usedStrings.add(option.stringIndex);
      current[noteIndex] = option;
      _backtrack(playableIndices, cursor + 1, optionsPerNote, usedStrings, current, results);
      usedStrings.remove(option.stringIndex);
      current[noteIndex] = null;
    }
    if (!placedAny) {
      // This note can't be placed on any free string in this branch;
      // leave it unassigned and continue so the rest of the chord still
      // gets a fingering.
      _backtrack(playableIndices, cursor + 1, optionsPerNote, usedStrings, current, results);
    }
  }

  _Fingering _greedyFingering(
    List<int> playableIndices,
    List<List<FretboardPosition>> optionsPerNote,
    int totalNotes,
  ) {
    final positions = List<FretboardPosition?>.filled(totalNotes, null);
    final usedStrings = <int>{};
    for (final noteIndex in playableIndices) {
      for (final option in optionsPerNote[noteIndex]) {
        if (!usedStrings.contains(option.stringIndex)) {
          usedStrings.add(option.stringIndex);
          positions[noteIndex] = option;
          break;
        }
      }
    }
    return _Fingering(positions);
  }
}
