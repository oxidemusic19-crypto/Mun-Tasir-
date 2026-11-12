import 'package:flutter/material.dart';

void main() => runApp(const PartySyncApp());

const bg = Color(0xFF0B0D17);
const panel = Color(0xFF171A2A);
const purple = Color(0xFF9B7BFF);
const cyan = Color(0xFF54D9E8);

class PartySyncApp extends StatelessWidget {
  const PartySyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PartySync',
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: purple,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final roomController = TextEditingController();
  bool inRoom = false;
  bool isHost = false;
  bool playing = false;
  String roomCode = '482913';
  String track = 'No track selected';
  int members = 1;
  double volume = 0.8;

  @override
  void dispose() {
    roomController.dispose();
    super.dispose();
  }

  void createRoom() {
    setState(() {
      inRoom = true;
      isHost = true;
      members = 1;
    });
  }

  void joinRoom() {
    if (roomController.text.trim().isEmpty) return;
    setState(() {
      inRoom = true;
      isHost = false;
      roomCode = roomController.text.trim();
      members = 2;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: inRoom ? roomScreen() : homeScreen(),
        ),
      ),
    );
  }

  Widget homeScreen() => Padding(
    key: const ValueKey('home'),
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 28),
        Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: purple.withOpacity(.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.graphic_eq, color: purple, size: 30),
          ),
          const SizedBox(width: 12),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('PartySync', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
            Text('Your phones. One sound system.', style: TextStyle(color: Colors.white60)),
          ]),
        ]),
        const SizedBox(height: 42),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF292044), Color(0xFF142B3C)]),
            borderRadius: BorderRadius.circular(24),
          ),
          child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.waves, color: cyan, size: 36),
            SizedBox(height: 12),
            Text('Turn your group into a speaker system',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text('Connect nearby phones and play music together. No internet planned for local rooms.',
              style: TextStyle(color: Colors.white70, height: 1.4)),
          ]),
        ),
        const SizedBox(height: 28),
        const Text('START A PARTY', style: TextStyle(letterSpacing: 1.5, color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 58,
          child: FilledButton.icon(
            onPressed: createRoom,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('Create Room', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 22),
        const Text('JOIN A ROOM', style: TextStyle(letterSpacing: 1.5, color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(
            controller: roomController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: 'Enter room code',
              filled: true,
              fillColor: panel,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          )),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: joinRoom,
            style: FilledButton.styleFrom(backgroundColor: cyan, foregroundColor: bg, padding: const EdgeInsets.symmetric(vertical: 18)),
            child: const Text('Join'),
          ),
        ]),
        const Spacer(),
        const Center(child: Text('Prototype • Local sync engine not connected yet', style: TextStyle(color: Colors.white38, fontSize: 11))),
      ],
    ),
  );

  Widget roomScreen() => Padding(
    key: const ValueKey('room'),
    padding: const EdgeInsets.all(22),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        IconButton(onPressed: () => setState(() => inRoom = false), icon: const Icon(Icons.arrow_back)),
        const SizedBox(width: 4),
        const Text('Party Room', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
        const Spacer(),
        const Icon(Icons.wifi, color: cyan),
      ]),
      const SizedBox(height: 20),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20)),
        child: Column(children: [
          const Text('ROOM CODE', style: TextStyle(color: Colors.white54, letterSpacing: 2, fontSize: 11)),
          const SizedBox(height: 8),
          Text(roomCode, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 5, color: cyan)),
          const SizedBox(height: 8),
          Text(isHost ? 'You are the Host' : 'Connected as Guest', style: const TextStyle(color: Colors.white70)),
        ]),
      ),
      const SizedBox(height: 20),
      Row(children: [
        const Text('Connected phones', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        const Spacer(),
        Text('$members / 10', style: const TextStyle(color: cyan, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          const CircleAvatar(backgroundColor: Color(0xFF34304F), child: Icon(Icons.smartphone, color: purple)),
          const SizedBox(width: 12),
          Expanded(child: Text(isHost ? 'This phone • Host' : 'This phone • Guest')),
          const Icon(Icons.check_circle, color: Colors.greenAccent),
        ]),
      ),
      const SizedBox(height: 22),
      const Text('NOW PLAYING', style: TextStyle(color: Colors.white54, letterSpacing: 1.5, fontSize: 11)),
      const SizedBox(height: 10),
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF27213F), Color(0xFF142B38)]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(children: [
          Container(
            height: 145, width: 145,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(colors: [purple, cyan], begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: const Icon(Icons.music_note, size: 76, color: Colors.white),
          ),
          const SizedBox(height: 14),
          Text(track, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          const Text('PartySync local player', style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          Row(children: const [
            Text('0:00', style: TextStyle(color: Colors.white54, fontSize: 11)),
            Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: LinearProgressIndicator(value: 0, color: cyan, backgroundColor: Colors.white12))),
            Text('0:00', style: TextStyle(color: Colors.white54, fontSize: 11)),
          ]),
          const SizedBox(height: 14),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            IconButton(onPressed: isHost ? () {} : null, icon: const Icon(Icons.skip_previous, size: 30)),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: () => setState(() => playing = !playing),
              style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(18), backgroundColor: purple),
              child: Icon(playing ? Icons.pause : Icons.play_arrow, size: 32),
            ),
            const SizedBox(width: 12),
            IconButton(onPressed: isHost ? () {} : null, icon: const Icon(Icons.skip_next, size: 30)),
          ]),
          if (isHost) TextButton.icon(
            onPressed: () => setState(() => track = 'Demo track (audio not loaded)'),
            icon: const Icon(Icons.upload_file),
            label: const Text('Choose music (demo)'),
          ),
        ]),
      ),
      const SizedBox(height: 18),
      Row(children: const [Icon(Icons.volume_up, color: cyan), SizedBox(width: 8), Text('This phone volume')]),
      Slider(value: volume, onChanged: (v) => setState(() => volume = v), activeColor: cyan),
      const Spacer(),
      const Text('Demo UI only: real hotspot discovery, audio streaming/cache and clock sync are the next development steps.',
        style: TextStyle(color: Colors.white38, fontSize: 11), textAlign: TextAlign.center),
    ]),
  );
}
