/// Instruments RiffNote can transcribe, per the project brief (section 3).
///
/// Only guitar and bass get string/fret assignment (section 5). Voice has
/// no tab, just the staff. Winds get concert-pitch notes now and
/// transposition later (section 6) — not implemented yet.
enum Instrument {
  guitar('Chitarra'),
  bass('Basso'),
  voice('Voce'),
  winds('Fiati');

  const Instrument(this.label);

  final String label;

  bool get hasStringFretAssignment =>
      this == Instrument.guitar || this == Instrument.bass;
}

/// A stringed instrument's open-string tuning, low to high, plus how far up
/// the neck RiffNote is willing to place a fretted note.
class StringTuning {
  const StringTuning({required this.openStringMidi, required this.maxFret});

  /// MIDI pitch of each open string, ordered low (index 0) to high.
  final List<int> openStringMidi;

  final int maxFret;

  int get stringCount => openStringMidi.length;

  static const guitarStandard = StringTuning(
    // E2 A2 D3 G3 B3 E4
    openStringMidi: [40, 45, 50, 55, 59, 64],
    maxFret: 20,
  );

  static const bassStandard = StringTuning(
    // E1 A1 D2 G2
    openStringMidi: [28, 33, 38, 43],
    maxFret: 20,
  );

  static StringTuning? forInstrument(Instrument instrument) {
    switch (instrument) {
      case Instrument.guitar:
        return guitarStandard;
      case Instrument.bass:
        return bassStandard;
      case Instrument.voice:
      case Instrument.winds:
        return null;
    }
  }
}
