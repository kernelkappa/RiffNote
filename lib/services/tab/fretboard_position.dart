/// A single fretted (or open) position on a stringed instrument.
///
/// [stringIndex] is 0-based, low to high (0 = thickest/lowest string),
/// matching [StringTuning.openStringMidi]. Display code converts this to
/// the usual guitarist numbering (string 1 = highest, thinnest) separately.
class FretboardPosition {
  const FretboardPosition({required this.stringIndex, required this.fret});

  final int stringIndex;
  final int fret;

  bool get isOpenString => fret == 0;
}

/// A detected note together with where to play it, or `null` in
/// [position] if no playable position was found (out of the instrument's
/// range, or it couldn't fit alongside simultaneous notes on the available
/// strings).
class PlayedNote {
  const PlayedNote({required this.midiPitch, required this.position});

  final int midiPitch;
  final FretboardPosition? position;
}
