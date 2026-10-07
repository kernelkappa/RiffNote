import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/recording.dart';
import '../screens/home_screen.dart' show recordingDateFormat;
import '../screens/transcribe_screen.dart';
import 'instrument_picker.dart';

/// A single row in the recordings list: play/stop, timestamp, delete.
class RecordingTile extends StatefulWidget {
  const RecordingTile({super.key, required this.recording, required this.onDelete});

  final Recording recording;
  final VoidCallback onDelete;

  @override
  State<RecordingTile> createState() => _RecordingTileState();
}

class _RecordingTileState extends State<RecordingTile> {
  final _player = AudioPlayer();
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (_isPlaying) {
      await _player.stop();
      setState(() => _isPlaying = false);
    } else {
      await _player.play(DeviceFileSource(widget.recording.path));
      setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fileName = p.basename(widget.recording.path);
    return ListTile(
      leading: IconButton(
        icon: Icon(_isPlaying ? Icons.stop_circle : Icons.play_circle),
        onPressed: _togglePlayback,
      ),
      title: Text(recordingDateFormat.format(widget.recording.createdAt)),
      subtitle: Text(fileName, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.graphic_eq),
            tooltip: 'Trascrivi',
            onPressed: () => _startTranscription(context),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  Future<void> _startTranscription(BuildContext context) async {
    final instrument = await pickInstrument(context);
    if (instrument == null || !context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranscribeScreen(
          recording: widget.recording,
          instrument: instrument,
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la registrazione?'),
        content: const Text('L\'operazione non è reversibile.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      widget.onDelete();
    }
  }
}
