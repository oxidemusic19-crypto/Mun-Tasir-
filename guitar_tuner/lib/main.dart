import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:record/record.dart';

void main() => runApp(const GuitarTuneApp());

const bg = Color(0xFF090D16);
const panel = Color(0xFF151D2B);
const mint = Color(0xFF6DE6C1);
const muted = Color(0xFF9AA9BA);

class Tuning {
  final String name;
  final List<String> strings; // low to high
  const Tuning(this.name, this.strings);
}

const tunings = <Tuning>[
  Tuning('Standard E', ['E2','A2','D3','G3','B3','E4']),
  Tuning('Half Step Down', ['Eb2','Ab2','Db3','Gb3','Bb3','Eb4']),
  Tuning('Full Step Down', ['D2','G2','C3','F3','A3','D4']),
  Tuning('Drop D', ['D2','A2','D3','G3','B3','E4']),
  Tuning('Drop C', ['C2','G2','C3','F3','A3','D4']),
  Tuning('Double Drop D', ['D2','A2','D3','G3','B3','D4']),
  Tuning('Open D', ['D2','A2','D3','F#3','A3','D4']),
  Tuning('Open D minor', ['D2','A2','D3','F3','A3','D4']),
  Tuning('Open G', ['D2','G2','D3','G3','B3','D4']),
  Tuning('Open C', ['C2','G2','C3','G3','C4','E4']),
  Tuning('Open E', ['E2','B2','E3','G#3','B3','E4']),
  Tuning('Open A', ['E2','A2','E3','A3','C#4','E4']),
  Tuning('DADGAD', ['D2','A2','D3','G3','A3','D4']),
  Tuning('C Standard', ['C2','F2','Bb2','Eb3','G3','C4']),
  Tuning('Baritone B', ['B1','E2','A2','D3','F#3','B3']),
  Tuning('Nashville', ['E3','A3','D4','G4','B3','E4']),
];

const noteNames = ['C','C#','D','D#','E','F','F#','G','G#','A','A#','B'];
final Map<String, double> noteFreq = {
  for (int midi = 24; midi <= 95; midi++)
    '${noteNames[midi % 12]}${midi ~/ 12 - 1}': 440 * pow(2, (midi - 69) / 12).toDouble(),
};

class Pitch {
  final double hz;
  final String note;
  final double cents;
  const Pitch(this.hz, this.note, this.cents);
}

Pitch? detectPitch(Uint8List bytes, int sampleRate) {
  final count = bytes.length ~/ 2;
  if (count < 2048) return null;
  final data = Int16List.view(bytes.buffer, bytes.offsetInBytes, count);
  double mean = 0;
  for (final v in data) { mean += v; }
  mean /= count;
  final x = List<double>.generate(count, (i) => (data[i] - mean) * (0.5 - 0.5 * cos(2 * pi * i / (count - 1))));
  double rms = 0;
  for (final v in x) { rms += v * v; }
  rms = sqrt(rms / count);
  if (rms < 120) return null;
  const minHz = 65.0, maxHz = 1000.0;
  final minLag = (sampleRate / maxHz).floor();
  final maxLag = min((sampleRate / minHz).ceil(), count ~/ 2);
  final corr = List<double>.filled(maxLag + 1, 0);
  for (int lag = minLag; lag <= maxLag; lag++) {
    double sum = 0;
    for (int i = 0; i < count - lag; i++) { sum += x[i] * x[i + lag]; }
    corr[lag] = sum;
  }
  int best = minLag;
  for (int lag = minLag + 1; lag < maxLag; lag++) {
    if (corr[lag] > corr[best]) best = lag;
  }
  if (corr[best] <= 0) return null;
  // Prefer the first strong local peak to reduce octave errors.
  final threshold = corr[best] * 0.88;
  for (int lag = minLag + 1; lag < best; lag++) {
    if (corr[lag] > threshold && corr[lag] >= corr[lag - 1] && corr[lag] >= corr[lag + 1]) {
      best = lag; break;
    }
  }
  double refined = best.toDouble();
  if (best > minLag && best < maxLag) {
    final a = corr[best - 1], b = corr[best], c = corr[best + 1];
    final denom = a - 2 * b + c;
    if (denom.abs() > 1e-9) refined += 0.5 * (a - c) / denom;
  }
  final hz = sampleRate / refined;
  if (!hz.isFinite || hz < minHz || hz > maxHz) return null;
  final midi = (69 + 12 * log(hz / 440) / ln2).round();
  final name = '${noteNames[midi % 12]}${midi ~/ 12 - 1}';
  final target = 440 * pow(2, (midi - 69) / 12);
  final cents = 1200 * log(hz / target) / ln2;
  return Pitch(hz, name, cents);
}

class GuitarTuneApp extends StatelessWidget {
  const GuitarTuneApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'GuitarTune Pro',
    theme: ThemeData.dark().copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(seedColor: mint, brightness: Brightness.dark),
      useMaterial3: true,
    ),
    home: const TunerPage(),
  );
}

class TunerPage extends StatefulWidget {
  const TunerPage({super.key});
  @override
  State<TunerPage> createState() => _TunerPageState();
}

class _TunerPageState extends State<TunerPage> {
  final recorder = AudioRecorder();
  StreamSubscription<Uint8List>? subscription;
  Tuning tuning = tunings.first;
  Pitch? pitch;
  bool listening = false;
  bool chromatic = false;
  String status = 'Tap Start and pluck one string';
  int selectedString = 0;
  int sampleRate = 44100;
  final List<double> recent = [];

  Future<void> toggle() async {
    if (listening) {
      await subscription?.cancel();
      subscription = null;
      await recorder.stop();
      if (mounted) setState(() { listening = false; status = 'Tuner paused'; });
      return;
    }
    try {
      if (!await recorder.hasPermission()) {
        setState(() => status = 'Microphone permission is required');
        return;
      }
      final stream = await recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
      ));
      recent.clear();
      subscription = stream.listen((bytes) {
        final detected = detectPitch(bytes, sampleRate);
        if (detected == null) return;
        recent.add(detected.hz);
        if (recent.length > 5) recent.removeAt(0);
        final sorted = [...recent]..sort();
        final hz = sorted[sorted.length ~/ 2];
        final midi = (69 + 12 * log(hz / 440) / ln2).round();
        final note = '${noteNames[midi % 12]}${midi ~/ 12 - 1}';
        final target = 440 * pow(2, (midi - 69) / 12);
        final cents = 1200 * log(hz / target) / ln2;
        if (mounted) setState(() { pitch = Pitch(hz, note, cents); status = 'Listening • pluck one string at a time'; });
      }, onError: (_) { if (mounted) setState(() => status = 'Audio input error. Restart the tuner.'); });
      setState(() { listening = true; status = 'Listening • pluck one string at a time'; });
    } catch (e) {
      setState(() => status = 'Could not start microphone: $e');
    }
  }

  @override
  void dispose() {
    subscription?.cancel();
    recorder.dispose();
    super.dispose();
  }

  double get cents => pitch?.cents ?? 0;
  String get verdict => pitch == null ? '—' : cents.abs() <= 1 ? 'PERFECT' : cents < 0 ? 'TOO LOW · TIGHTEN' : 'TOO HIGH · LOOSEN';
  String get targetString => tuning.strings[selectedString];

  @override
  Widget build(BuildContext context) {
    final diff = pitch == null ? 0.0 : cents.clamp(-50, 50).toDouble();
    return Scaffold(
      appBar: AppBar(
        backgroundColor: bg,
        title: const Row(children: [Icon(Icons.graphic_eq, color: mint), SizedBox(width: 10), Text('GuitarTune Pro', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: .3))]),
        actions: [IconButton(onPressed: () => showAboutDialog(context: context, applicationName: 'GuitarTune Pro', applicationVersion: '0.1.0', children: const [Text('A microphone-based guitar tuner. Accuracy depends on your phone microphone, string condition and background noise.')]), icon: const Icon(Icons.info_outline))],
      ),
      body: SafeArea(child: ListView(padding: const EdgeInsets.fromLTRB(18, 4, 18, 28), children: [
        Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(18)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('TUNING PRESET', style: TextStyle(color: muted, fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          DropdownButtonFormField<Tuning>(
            value: tuning,
            isExpanded: true,
            decoration: InputDecoration(filled: true, fillColor: bg, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4)),
            items: tunings.map((t) => DropdownMenuItem(value: t, child: Text(t.name))).toList(),
            onChanged: (t) { if (t != null) setState(() { tuning = t; selectedString = 0; chromatic = false; }); },
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text('Chromatic mode', style: TextStyle(color: muted))),
            Switch(value: chromatic, activeColor: mint, onChanged: (v) => setState(() => chromatic = v)),
          ]),
        ])),
        const SizedBox(height: 16),
        Container(padding: const EdgeInsets.fromLTRB(16, 18, 16, 20), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(22)), child: Column(children: [
          Text(chromatic ? 'CHROMATIC' : 'TARGET STRING', style: const TextStyle(color: muted, letterSpacing: 1.8, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (!chromatic) Wrap(spacing: 8, children: List.generate(tuning.strings.length, (i) => ChoiceChip(
            label: Text('${i + 1} · ${tuning.strings[i]}'),
            selected: selectedString == i,
            selectedColor: mint,
            labelStyle: TextStyle(color: selectedString == i ? bg : Colors.white),
            onSelected: (_) => setState(() => selectedString = i),
          ))),
          const SizedBox(height: 14),
          Text(pitch?.note ?? '—', style: const TextStyle(fontSize: 76, height: 1, fontWeight: FontWeight.w800, color: mint)),
          Text(pitch == null ? (chromatic ? 'Waiting for a note' : 'Target: $targetString') : '${pitch!.hz.toStringAsFixed(2)} Hz', style: const TextStyle(color: muted, fontSize: 14)),
          const SizedBox(height: 22),
          SizedBox(height: 74, child: CustomPaint(size: const Size(double.infinity, 74), painter: MeterPainter(diff, pitch != null))),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('♭  LOW', style: TextStyle(color: muted, fontSize: 11)), Text('IN TUNE', style: TextStyle(color: mint, fontSize: 11, fontWeight: FontWeight.bold)), Text('HIGH  ♯', style: TextStyle(color: muted, fontSize: 11))]),
          const SizedBox(height: 14),
          Text(pitch == null ? '0 cents' : '${cents > 0 ? '+' : ''}${cents.toStringAsFixed(1)} cents', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(verdict, style: TextStyle(color: pitch == null ? muted : cents.abs() <= 1 ? mint : Colors.orangeAccent, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
        ])),
        const SizedBox(height: 16),
        SizedBox(height: 58, child: FilledButton.icon(
          onPressed: toggle,
          style: FilledButton.styleFrom(backgroundColor: listening ? const Color(0xFFB54D5C) : mint, foregroundColor: bg, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
          icon: Icon(listening ? Icons.stop : Icons.mic),
          label: Text(listening ? 'STOP TUNER' : 'START TUNER', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        )),
        const SizedBox(height: 12),
        Text(status, textAlign: TextAlign.center, style: const TextStyle(color: muted, fontSize: 12)),
        const SizedBox(height: 22),
        const Text('TUNING GUIDE', style: TextStyle(color: muted, letterSpacing: 1.5, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(14)), child: const Text('1. Select a tuning preset.\n2. Select the string you want to tune.\n3. Pluck that string alone and let it ring.\n4. Adjust the tuning peg until the meter reaches the centre and reads PERFECT.\n\nTip: Tune in a quiet room, mute the other strings, and pluck gently.', style: TextStyle(color: muted, height: 1.55, fontSize: 13))),
        const SizedBox(height: 10),
        const Text('Pitch accuracy depends on microphone quality and room noise. This tuner estimates pitch from live audio; always verify by ear before performance.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF68798B), fontSize: 10)),
      ])),
    );
  }
}

class MeterPainter extends CustomPainter {
  final double cents;
  final bool active;
  MeterPainter(this.cents, this.active);
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.width / 2;
    final base = Paint()..color = const Color(0xFF334252)..strokeWidth = 5..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(8, size.height - 10), Offset(size.width - 8, size.height - 10), base);
    final tick = Paint()..color = const Color(0xFF718194)..strokeWidth = 2;
    for (int i = -5; i <= 5; i++) {
      final x = center + i * (size.width - 32) / 10;
      canvas.drawLine(Offset(x, size.height - (i == 0 ? 32 : 22)), Offset(x, size.height - 6), tick);
    }
    final x = center + cents.clamp(-50, 50) / 50 * (size.width / 2 - 18);
    final needle = Paint()..color = (!active ? muted : cents.abs() <= 1 ? mint : Colors.orangeAccent)..strokeWidth = 4..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(x, 5), Offset(x, size.height - 15), needle);
    canvas.drawCircle(Offset(x, 5), 5, Paint()..color = needle.color);
  }
  @override
  bool shouldRepaint(covariant MeterPainter old) => old.cents != cents || old.active != active;
}
