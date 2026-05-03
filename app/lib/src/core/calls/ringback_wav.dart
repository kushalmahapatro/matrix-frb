import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Writes a short dual-tone WAV (8 kHz mono) for outgoing-call ringback; cached in temp dir.
Future<File> ensureRingbackWavFile() async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/matrix_ringback.wav');
  if (await f.exists()) return f;
  await f.writeAsBytes(buildRingbackWavBytes());
  return f;
}

Uint8List buildRingbackWavBytes() {
  const sampleRate = 8000;
  const seconds = 2;
  final n = sampleRate * seconds;
  final pcm = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = 0.18 *
        (math.sin(2 * math.pi * 440 * t) + math.sin(2 * math.pi * 480 * t));
    pcm[i] = (v * 32767).clamp(-32768, 32767).toInt();
  }
  return _pcm16MonoToWav(pcm, sampleRate);
}

Uint8List _pcm16MonoToWav(Int16List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final chunkSize = 36 + dataSize;
  final out = Uint8List(44 + dataSize);
  final bd = ByteData.sublistView(out);

  void writeAscii(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      out[offset + i] = s.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  bd.setUint32(4, chunkSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  bd.setUint32(16, 16, Endian.little);
  bd.setUint16(20, 1, Endian.little);
  bd.setUint16(22, 1, Endian.little);
  bd.setUint32(24, sampleRate, Endian.little);
  bd.setUint32(28, sampleRate * 2, Endian.little);
  bd.setUint16(32, 2, Endian.little);
  bd.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  bd.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(44 + i * 2, samples[i], Endian.little);
  }
  return out;
}
