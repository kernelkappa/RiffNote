const _noteNames = [
  'C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B',
];

/// Scientific pitch notation for a MIDI note number, e.g. 69 -> "A4".
String midiToNoteName(int midiPitch) {
  final octave = (midiPitch ~/ 12) - 1;
  final name = _noteNames[midiPitch % 12];
  return '$name$octave';
}
