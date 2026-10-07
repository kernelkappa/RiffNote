import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/recording.dart';

/// Reads and writes recordings under the app's documents directory.
///
/// Everything stays on-device, in a dedicated `recordings/` subfolder, so
/// that it never mixes with other app data and is trivial to reason about
/// (and to wipe) later.
class RecordingRepository {
  static const _subfolder = 'recordings';

  Future<Directory> _recordingsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(appDir.path, _subfolder));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Builds a fresh, timestamped file path for a new recording.
  /// Does not create the file: the recorder itself writes to this path.
  Future<String> newRecordingPath({String extension = 'wav'}) async {
    final dir = await _recordingsDir();
    final timestamp = DateTime.now().toIso8601String().replaceAll(
      RegExp(r'[:.]'),
      '-',
    );
    return p.join(dir.path, 'riffnote_$timestamp.$extension');
  }

  /// Lists all saved recordings, most recent first.
  Future<List<Recording>> listRecordings() async {
    final dir = await _recordingsDir();
    final entries = await dir.list().toList();
    final files = entries.whereType<File>();

    final recordings = <Recording>[];
    for (final file in files) {
      final stat = await file.stat();
      recordings.add(Recording(file: file, createdAt: stat.modified));
    }
    recordings.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return recordings;
  }

  Future<void> delete(Recording recording) async {
    if (await recording.file.exists()) {
      await recording.file.delete();
    }
  }
}
