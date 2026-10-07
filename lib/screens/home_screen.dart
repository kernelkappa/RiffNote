import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';

import '../models/recording.dart';
import '../services/basic_pitch/basic_pitch_constants.dart' as basic_pitch;
import '../services/recording_repository.dart';
import '../widgets/recording_tile.dart';

/// Home screen: record a new take and browse past recordings.
///
/// Step 1 of the roadmap in the project brief (audio capture and local
/// storage) plus step 2 (on-device transcription via [RecordingTile]'s
/// "Trascrivi" action).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _recorder = AudioRecorder();
  final _repository = RecordingRepository();

  bool _isRecording = false;
  List<Recording> _recordings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshRecordings();
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _refreshRecordings() async {
    final recordings = await _repository.listRecordings();
    if (!mounted) return;
    setState(() {
      _recordings = recordings;
      _isLoading = false;
    });
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (!mounted) return;
      _showMessage('Permesso microfono negato.');
      return;
    }

    final path = await _repository.newRecordingPath();
    // WAV PCM16 mono @ 22050 Hz: exactly the format Basic Pitch's model
    // expects, so transcription never has to decode or resample audio.
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        sampleRate: basic_pitch.audioSampleRate,
        numChannels: 1,
      ),
      path: path,
    );

    setState(() {
      _isRecording = true;
    });
  }

  Future<void> _stopRecording() async {
    await _recorder.stop();
    setState(() {
      _isRecording = false;
    });
    await _refreshRecordings();
  }

  Future<void> _deleteRecording(Recording recording) async {
    await _repository.delete(recording);
    await _refreshRecordings();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('RiffNote')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _recordings.isEmpty
              ? const _EmptyState()
              : ListView.builder(
                  itemCount: _recordings.length,
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    return RecordingTile(
                      recording: recording,
                      onDelete: () => _deleteRecording(recording),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleRecording,
        backgroundColor: _isRecording ? Colors.red : null,
        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
        label: Text(_isRecording ? 'Stop' : 'Registra'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_none, size: 64, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            const Text(
              'Nessuna registrazione ancora.\nPremi "Registra" per catturare un riff.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared date formatter for recording timestamps.
final recordingDateFormat = DateFormat('dd/MM/yyyy HH:mm:ss');
