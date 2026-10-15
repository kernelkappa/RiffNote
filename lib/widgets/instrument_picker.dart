import 'package:flutter/material.dart';

import '../models/instrument.dart';

/// Per the project brief (section 2): the user always picks the instrument
/// before transcribing — RiffNote never guesses it. Shown right before
/// transcription starts.
///
/// Flat list (no "Fiati" category step): with 12 instruments it's one tap
/// shorter than a two-level picker, at the cost of a longer, scrollable
/// list.
Future<Instrument?> pickInstrument(BuildContext context) {
  return showModalBottomSheet<Instrument>(
    context: context,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Che strumento hai registrato?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    for (final instrument in Instrument.values)
                      ListTile(
                        leading: Icon(_iconFor(instrument)),
                        title: Text(instrument.label),
                        onTap: () => Navigator.of(context).pop(instrument),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

IconData _iconFor(Instrument instrument) {
  switch (instrument) {
    case Instrument.guitar:
      return Icons.music_note;
    case Instrument.bass:
      return Icons.graphic_eq;
    case Instrument.voice:
      return Icons.mic;
    default:
      // All winds (flute through horn): no dedicated Material icon per
      // instrument, so a shared "air" icon stands in for the whole family.
      return Icons.air;
  }
}
