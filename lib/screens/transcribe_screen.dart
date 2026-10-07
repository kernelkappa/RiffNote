import 'package:flutter/material.dart';

import '../models/instrument.dart';
import '../models/recording.dart';
import '../services/basic_pitch/basic_pitch_service.dart';
import '../services/tab/chord_event.dart';
import '../services/tab/string_fret_assigner.dart';

/// Shows the notes Basic Pitch detects in a recording, grouped into chord
/// events and — for guitar/bass — with a string/fret position per note.
///
/// Still deliberately just a list, not tab/notation rendering: per the
/// project brief (section 12.2 / step 2 of the roadmap), the goal is to
/// judge transcription (and now fretting) quality, not ship a polished
/// editor yet.
class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({
    super.key,
    required this.recording,
    required this.instrument,
  });

  final Recording recording;
  final Instrument instrument;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  final _service = BasicPitchService();

  late Future<List<ChordEvent>> _eventsFuture;

  @override
  void initState() {
    super.initState();
    _eventsFuture = _transcribe();
  }

  StringTuning? get _tuning => StringTuning.forInstrument(widget.instrument);

  Future<List<ChordEvent>> _transcribe() async {
    final notes = await _service.transcribeFile(widget.recording.file);
    final events = groupIntoChordEvents(notes);

    final tuning = _tuning;
    if (tuning != null) {
      StringFretAssigner(tuning).assign(events);
    }
    return events;
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Note rilevate · ${widget.instrument.label}'),
      ),
      body: FutureBuilder<List<ChordEvent>>(
        future: _eventsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Trascrizione in corso (Basic Pitch on-device)...'),
                  ],
                ),
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Trascrizione non riuscita:\n${snapshot.error}',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final events = snapshot.data!;
          if (events.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Nessuna nota rilevata.\nProva con una registrazione più '
                  'pulita o più lunga.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          return ListView.separated(
            itemCount: events.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _ChordEventTile(
              event: events[index],
              tuning: _tuning,
            ),
          );
        },
      ),
    );
  }
}

class _ChordEventTile extends StatelessWidget {
  const _ChordEventTile({required this.event, required this.tuning});

  final ChordEvent event;
  final StringTuning? tuning;

  @override
  Widget build(BuildContext context) {
    final isChord = event.notes.length > 1;
    final endTime = event.notes
        .map((n) => n.endTimeSec)
        .reduce((a, b) => a > b ? a : b);

    return ListTile(
      leading: CircleAvatar(
        child: Text(isChord ? '${event.notes.length}' : event.notes.first.noteName),
      ),
      title: Text(
        '${event.startTimeSec.toStringAsFixed(2)}s → ${endTime.toStringAsFixed(2)}s'
        '${isChord ? "  (accordo)" : ""}',
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < event.notes.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(_describeNote(event, i)),
            ),
        ],
      ),
      isThreeLine: event.notes.length > 2,
    );
  }

  String _describeNote(ChordEvent event, int index) {
    final note = event.notes[index];
    final base = '${note.noteName} · ampiezza ${(note.amplitude * 100).round()}%';
    final tuning = this.tuning;
    if (tuning == null || event.playedNotes.isEmpty) return base;

    final position = event.playedNotes[index].position;
    if (position == null) {
      return '$base · non suonabile su questo manico';
    }
    // Guitarist convention: string 1 = highest/thinnest, so reverse the
    // internal low-to-high index.
    final stringNumber = tuning.stringCount - position.stringIndex;
    return '$base · corda $stringNumber, tasto ${position.fret}';
  }
}
