import 'package:flutter/material.dart';

import '../models/recording.dart';
import '../services/basic_pitch/basic_pitch_service.dart';
import '../services/basic_pitch/note_decoder.dart';

/// Shows the notes Basic Pitch detects in a recording.
///
/// This is deliberately just a list, not tab/notation rendering: per the
/// project brief (section 12.2 / step 2 of the roadmap), the goal right now
/// is to judge whether the on-device transcription quality is good enough
/// to build the rest of the app on — not to ship a polished editor.
class TranscribeScreen extends StatefulWidget {
  const TranscribeScreen({super.key, required this.recording});

  final Recording recording;

  @override
  State<TranscribeScreen> createState() => _TranscribeScreenState();
}

class _TranscribeScreenState extends State<TranscribeScreen> {
  final _service = BasicPitchService();

  late Future<List<DetectedNote>> _notesFuture;

  @override
  void initState() {
    super.initState();
    _notesFuture = _service.transcribeFile(widget.recording.file);
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Note rilevate')),
      body: FutureBuilder<List<DetectedNote>>(
        future: _notesFuture,
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

          final notes = snapshot.data!;
          if (notes.isEmpty) {
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
            itemCount: notes.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final note = notes[index];
              return ListTile(
                leading: CircleAvatar(child: Text(note.noteName)),
                title: Text(
                  '${note.startTimeSec.toStringAsFixed(2)}s → '
                  '${note.endTimeSec.toStringAsFixed(2)}s',
                ),
                subtitle: Text(
                  'Durata ${(note.durationSec * 1000).round()} ms · '
                  'MIDI ${note.midiPitch} · '
                  'ampiezza ${(note.amplitude * 100).round()}%',
                ),
              );
            },
          );
        },
      ),
    );
  }
}
