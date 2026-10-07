import 'dart:io';
import 'dart:typed_data';

/// Decoded PCM audio: mono samples in the [-1.0, 1.0] range, plus the
/// sample rate actually stored in the file (so callers can refuse files
/// that don't match what Basic Pitch expects instead of silently
/// mis-reading them).
class DecodedWav {
  DecodedWav({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// Minimal parser for the WAV files produced by the `record` package with
/// `AudioEncoder.wav` (canonical PCM, 16-bit, mono or stereo).
///
/// Basic Pitch's model expects mono float32 samples at 22050 Hz, so
/// RiffNote records directly in that format — this parser doesn't resample
/// or handle exotic WAV variants (float PCM, extensible fmt chunks, etc.)
/// on purpose: it only needs to read back what we ourselves wrote.
class WavDecoder {
  static Future<DecodedWav> decodeFile(File file) async {
    final bytes = await file.readAsBytes();
    return decodeBytes(bytes);
  }

  static DecodedWav decodeBytes(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);

    String fourCc(int offset) =>
        String.fromCharCodes(bytes.sublist(offset, offset + 4));

    if (fourCc(0) != 'RIFF' || fourCc(8) != 'WAVE') {
      throw const FormatException('Not a RIFF/WAVE file.');
    }

    int? numChannels;
    int? sampleRate;
    int? bitsPerSample;
    int? dataOffset;
    int? dataLength;

    var offset = 12; // after "RIFF"<size>"WAVE"
    while (offset + 8 <= bytes.length) {
      final chunkId = fourCc(offset);
      final chunkSize = data.getUint32(offset + 4, Endian.little);
      final chunkDataStart = offset + 8;

      if (chunkId == 'fmt ') {
        numChannels = data.getUint16(chunkDataStart + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataStart + 4, Endian.little);
        bitsPerSample = data.getUint16(chunkDataStart + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataStart;
        dataLength = chunkSize;
      }

      // Chunks are padded to even length.
      offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
    }

    if (numChannels == null ||
        sampleRate == null ||
        bitsPerSample == null ||
        dataOffset == null ||
        dataLength == null) {
      throw const FormatException('Missing fmt or data chunk in WAV file.');
    }
    if (bitsPerSample != 16) {
      throw FormatException(
        'Only 16-bit PCM WAV is supported, got $bitsPerSample bits.',
      );
    }

    // Clamp in case the declared data length overruns the actual file
    // (can happen with files written while recording was interrupted).
    final availableBytes = bytes.length - dataOffset;
    final length = dataLength > availableBytes ? availableBytes : dataLength;

    final sampleCount = (length ~/ 2) ~/ numChannels;
    final mono = Float32List(sampleCount);

    for (var i = 0; i < sampleCount; i++) {
      var sum = 0;
      for (var ch = 0; ch < numChannels; ch++) {
        final byteOffset = dataOffset + (i * numChannels + ch) * 2;
        sum += data.getInt16(byteOffset, Endian.little);
      }
      mono[i] = (sum / numChannels) / 32768.0;
    }

    return DecodedWav(samples: mono, sampleRate: sampleRate);
  }
}
