/// Instruments RiffNote can transcribe, per the project brief (sections 3
/// and 6).
///
/// Only guitar and bass get string/fret assignment (section 5) — everything
/// else gets standard notation only. Winds are listed individually (not a
/// generic "Fiati" bucket) because each needs its own transposition from
/// concert pitch to written pitch, and has its own playable range; the user
/// still picks the instrument before transcribing, never guessed (section 2).
enum Instrument {
  guitar('Chitarra', transpositionSemitones: 0, concertRange: null),
  bass('Basso', transpositionSemitones: 0, concertRange: null),
  voice('Voce', transpositionSemitones: 0, concertRange: null),

  // Winds: transposition intervals (concert pitch -> written note) are from
  // the brief's own table (section 6), not guessed. Concert-pitch playable
  // ranges are typical/indicative (derived from commonly published written
  // ranges, converted to concert pitch by undoing the transposition) —
  // meant to flag obviously-out-of-range notes, not to be a hard
  // professional limit.
  flute('Flauto', transpositionSemitones: 0, concertRange: (60, 96)), // C4-C7
  oboe('Oboe', transpositionSemitones: 0, concertRange: (58, 91)), // Bb3-G6
  bassoon('Fagotto', transpositionSemitones: 0, concertRange: (34, 74)), // Bb1-D5
  clarinetBb(
    'Clarinetto in Sib',
    transpositionSemitones: 2,
    concertRange: (48, 92), // written D3-Bb6, concert = written-2
  ),
  trumpetBb(
    'Tromba in Sib',
    transpositionSemitones: 2,
    concertRange: (52, 84), // written F#3-D6, concert = written-2
  ),
  saxSoprano(
    'Sax soprano',
    transpositionSemitones: 2,
    concertRange: (56, 89), // written Bb3-G6, concert = written-2
  ),
  saxAlto(
    'Sax contralto',
    transpositionSemitones: 9,
    concertRange: (49, 82), // written Bb3-G6, concert = written-9
  ),
  saxTenor(
    'Sax tenore',
    transpositionSemitones: 14,
    concertRange: (44, 77), // written Bb3-G6, concert = written-14
  ),
  saxBaritone(
    'Sax baritono',
    transpositionSemitones: 21,
    concertRange: (37, 70), // written Bb3-G6, concert = written-21
  ),
  hornF(
    'Corno in Fa',
    transpositionSemitones: 7,
    concertRange: (47, 81), // written F#3-E6, concert = written-7
  );

  const Instrument(
    this.label, {
    required this.transpositionSemitones,
    required this.concertRange,
  });

  final String label;

  /// Semitones added to a concert-pitch MIDI note to get the written note
  /// for this instrument (brief section 6). 0 for non-transposing
  /// instruments (including guitar/bass/voice, which RiffNote never
  /// transposes).
  final int transpositionSemitones;

  /// Typical playable range in concert-pitch MIDI (min, max), or null for
  /// instruments RiffNote doesn't range-check (guitar/bass are constrained
  /// by [StringTuning] instead; voice isn't constrained at all).
  final (int min, int max)? concertRange;

  bool get hasStringFretAssignment =>
      this == Instrument.guitar || this == Instrument.bass;

  bool get isTransposing => transpositionSemitones != 0;
}

/// A stringed instrument's open-string tuning, low to high, plus how far up
/// the neck RiffNote is willing to place a fretted note.
class StringTuning {
  const StringTuning({
    required this.openStringMidi,
    required this.maxFret,
    required this.notationClef,
  });

  /// MIDI pitch of each open string, ordered low (index 0) to high.
  final List<int> openStringMidi;

  final int maxFret;

  /// alphaTex `\clef` keyword for this instrument's pitch range — guitar
  /// reads in treble clef, bass in bass clef. Explicit per tuning (not
  /// guessed from string count or pitch) so it stays correct if a
  /// different tuning is ever added.
  final String notationClef;

  int get stringCount => openStringMidi.length;

  static const guitarStandard = StringTuning(
    // E2 A2 D3 G3 B3 E4
    openStringMidi: [40, 45, 50, 55, 59, 64],
    maxFret: 20,
    notationClef: 'treble',
  );

  static const bassStandard = StringTuning(
    // E1 A1 D2 G2
    openStringMidi: [28, 33, 38, 43],
    maxFret: 20,
    notationClef: 'bass',
  );

  static StringTuning? forInstrument(Instrument instrument) {
    switch (instrument) {
      case Instrument.guitar:
        return guitarStandard;
      case Instrument.bass:
        return bassStandard;
      default:
        return null;
    }
  }
}
