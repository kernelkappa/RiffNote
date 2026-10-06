import 'dart:io';

/// A single audio recording saved locally on the device.
///
/// RiffNote never uploads audio anywhere: every [Recording] maps 1:1 to a
/// file under the app's documents directory.
class Recording {
  Recording({required this.file, required this.createdAt});

  final File file;
  final DateTime createdAt;

  String get path => file.path;

  Future<int> get sizeInBytes => file.length();
}
