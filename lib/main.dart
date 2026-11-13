import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const PartySyncApp());

const bg = Color(0xFF0B0D17);
const panel = Color(0xFF171A2A);
const purple = Color(0xFF9B7BFF);
const cyan = Color(0xFF54D9E8);
const port = 4040;

class PartySyncApp extends StatelessWidget {
  const PartySyncApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PartySync',
        theme: ThemeData(
          brightness: Brightness.dark,
          scaffoldBackgroundColor: bg,
          colorScheme: ColorScheme.fromSeed(seedColor: purple, brightness: Brightness.dark),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _ipController = TextEditingController();
  final _codeController = TextEditingController();
  final AudioPlayer _player = AudioPlayer();
  HttpServer? _server;
  WebSocket? _guestSocket;
  final Set<WebSocket> _clients = {};
  File? _hostAudioFile;
  String _roomCode = '';
  String _status = 'Not connected';
  String _hostIp = '';
  String _guestHostIp = '';
  String _role = '';
  String _trackName = 'No song selected';
  int _members = 1;
  bool _playing = false;
  bool _busy = false;
  bool _loadingTrack = false;

  @override
  void dispose() {
    _ipController.dispose();
    _codeController.dispose();
    _stopNetwork();
    _player.dispose();
    super.dispose();
  }

  String _newRoomCode() => (100000 + Random.secure().nextInt(900000)).toString();

  Future<void> _startHost() async {
    if (_busy || _server != null) return;
    setState(() { _busy = true; _status = 'Starting local server...'; });
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      _server = server;
      final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      final addresses = interfaces.expand((i) => i.addresses).where((a) => !a.isLoopback).map((a) => a.address).toList();
      _roomCode = _newRoomCode();
      _hostIp = addresses.isNotEmpty ? addresses.first : 'Check Wi-Fi details';
      _role = 'Host';
      _members = 1;
      _status = 'Room is ready';
      server.listen(_handleRequest, onError: (Object error) {
        if (mounted) setState(() => _status = 'Server error: $error');
      });
    } catch (error) {
      _status = 'Could not start server: $error';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/audio' && request.method == 'GET') {
      final file = _hostAudioFile;
      if (file == null || !await file.exists()) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      request.response.headers.contentType = ContentType.binary;
      request.response.headers.set(HttpHeaders.contentLengthHeader, await file.length());
      await request.response.addStream(file.openRead());
      await request.response.close();
      return;
    }
    if (request.uri.path != '/ws' || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response..statusCode = HttpStatus.notFound..write('PartySync local server');
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    socket.listen((raw) {
      try {
        final message = jsonDecode(raw as String) as Map<String, dynamic>;
        if (message['type'] == 'join') {
          if (message['code'] != _roomCode) {
            socket.add(jsonEncode({'type': 'error', 'message': 'Wrong room code'}));
            socket.close();
            return;
          }
          _clients.add(socket);
          socket.add(jsonEncode({'type': 'joined', 'room': _roomCode}));
          _broadcastMembers();
          if (_hostAudioFile != null) {
            socket.add(jsonEncode({'type': 'track', 'name': _trackName}));
          }
          if (mounted) setState(() { _members = _clients.length + 1; _status = 'Guest connected'; });
        } else if (message['type'] == 'control') {
          unawaited(_setPlayback(message['playing'] == true));
        }
      } catch (_) {
        socket.add(jsonEncode({'type': 'error', 'message': 'Invalid message'}));
      }
    }, onDone: () {
      _clients.remove(socket);
      _broadcastMembers();
      if (mounted) setState(() { _members = _clients.length + 1; _status = 'Guest disconnected'; });
    }, onError: (_) {
      _clients.remove(socket);
      _broadcastMembers();
    });
  }

  void _broadcast(Map<String, dynamic> message) {
    final data = jsonEncode(message);
    for (final client in _clients.toList()) {
      if (client.readyState == WebSocket.open) client.add(data);
    }
  }

  void _broadcastMembers() => _broadcast({'type': 'members', 'count': _clients.length + 1});

  Future<void> _joinRoom() async {
    if (_busy) return;
    final ip = _ipController.text.trim();
    final code = _codeController.text.trim();
    if (ip.isEmpty || code.isEmpty) {
      setState(() => _status = 'Enter host IP and room code');
      return;
    }
    setState(() { _busy = true; _status = 'Connecting to host...'; });
    try {
      final socket = await WebSocket.connect('ws://$ip:$port/ws').timeout(const Duration(seconds: 8));
      _guestSocket = socket;
      _guestHostIp = ip;
      socket.add(jsonEncode({'type': 'join', 'code': code}));
      socket.listen((raw) {
        final message = jsonDecode(raw as String) as Map<String, dynamic>;
        if (message['type'] == 'joined') {
          if (mounted) setState(() { _role = 'Guest'; _roomCode = code; _status = 'Connected to host'; });
        } else if (message['type'] == 'members') {
          if (mounted) setState(() => _members = message['count'] as int);
        } else if (message['type'] == 'playback') {
          if (mounted) setState(() => _playing = message['playing'] == true);
          if (message['playing'] == true) { unawaited(_player.play()); } else { unawaited(_player.pause()); }
        } else if (message['type'] == 'track') {
          unawaited(_downloadAndLoadTrack(message['name'] as String? ?? 'PartySync track'));
        } else if (message['type'] == 'error') {
          if (mounted) setState(() => _status = message['message'] as String);
        }
      }, onDone: () {
        if (mounted) setState(() => _status = 'Connection closed');
      }, onError: (Object error) {
        if (mounted) setState(() => _status = 'Connection error: $error');
      });
    } catch (error) {
      _status = 'Could not connect. Check IP, code and same Wi-Fi.';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseTrack() async {
    if (_role != 'Host' || _loadingTrack) return;
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      if (result == null || result.files.single.path == null) return;
      setState(() { _loadingTrack = true; _status = 'Loading selected song...'; });
      final file = File(result.files.single.path!);
      await _player.setFilePath(file.path);
      _hostAudioFile = file;
      _trackName = result.files.single.name;
      _broadcast({'type': 'track', 'name': _trackName});
      if (mounted) setState(() => _status = 'Song ready. Guests can download it.');
    } catch (error) {
      if (mounted) setState(() => _status = 'Could not load song: $error');
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
  }

  Future<void> _downloadAndLoadTrack(String name) async {
    if (_loadingTrack) return;
    setState(() { _loadingTrack = true; _status = 'Downloading song from host...'; });
    try {
      final client = HttpClient();
      final request = await client.getUrl(Uri.parse('http://$_guestHostIp:$port/audio'));
      final response = await request.close().timeout(const Duration(seconds: 60));
      if (response.statusCode != HttpStatus.ok) throw Exception('Host file unavailable');
      final directory = await getTemporaryDirectory();
      final safeName = name.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final file = File('${directory.path}/partysync_${DateTime.now().millisecondsSinceEpoch}_$safeName');
      final sink = file.openWrite();
      await response.pipe(sink);
      client.close();
      await _player.setFilePath(file.path);
      if (mounted) setState(() { _trackName = name; _status = 'Song downloaded and ready'; });
    } catch (error) {
      if (mounted) setState(() => _status = 'Song download failed: $error');
    } finally {
      if (mounted) setState(() => _loadingTrack = false);
    }
  }

  Future<void> _setPlayback(bool next) async {
    try {
      if (next) { await _player.play(); } else { await _player.pause(); }
      if (mounted) setState(() => _playing = next);
      _broadcast({'type': 'playback', 'playing': next});
    } catch (error) {
      if (mounted) setState(() => _status = 'Playback error: $error');
    }
  }

  void _togglePlayback() {
    final next = !_playing;
    if (_role == 'Host') {
      unawaited(_setPlayback(next));
    } else {
      _guestSocket?.add(jsonEncode({'type': 'control', 'playing': next}));
    }
  }

  Future<void> _stopNetwork() async {
    for (final client in _clients.toList()) { await client.close(); }
    _clients.clear();
    await _guestSocket?.close();
    await _server?.close(force: true);
    _guestSocket = null;
    _server = null;
  }

  Future<void> _leaveRoom() async {
    await _stopNetwork();
    await _player.stop();
    if (!mounted) return;
    setState(() {
      _role = ''; _roomCode = ''; _hostIp = ''; _guestHostIp = '';
      _members = 1; _playing = false; _trackName = 'No song selected';
      _hostAudioFile = null; _status = 'Not connected';
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: _role.isEmpty ? _homeScreen() : _roomScreen()));

  Widget _homeScreen() => ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 18),
          Row(children: [
            Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: purple.withOpacity(.16), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.graphic_eq, color: purple, size: 30)),
            const SizedBox(width: 12),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('PartySync', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
              Text('Your phones. One sound system.', style: TextStyle(color: Colors.white60)),
            ]),
          ]),
          const SizedBox(height: 30),
          _panel(child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.waves, color: cyan, size: 34), SizedBox(height: 10),
            Text('Connect phones over local Wi-Fi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('No internet is needed after the phones are connected to the same hotspot or Wi-Fi network.', style: TextStyle(color: Colors.white70, height: 1.4)),
          ])),
          const SizedBox(height: 24),
          const Text('HOST A PARTY', style: TextStyle(color: Colors.white54, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          const Text('First turn on your Android phone hotspot in Settings. Connect guest phones to it.', style: TextStyle(color: Colors.white60)),
          const SizedBox(height: 12),
          SizedBox(height: 54, child: FilledButton.icon(onPressed: _busy ? null : _startHost, icon: const Icon(Icons.wifi_tethering), label: Text(_busy ? 'Please wait...' : 'Start Host Room'), style: FilledButton.styleFrom(backgroundColor: purple, foregroundColor: Colors.white))),
          const SizedBox(height: 26),
          const Text('JOIN A PARTY', style: TextStyle(color: Colors.white54, letterSpacing: 1.4)),
          const SizedBox(height: 10),
          TextField(controller: _ipController, keyboardType: TextInputType.url, decoration: _decoration('Host IP address (e.g. 192.168.43.1)')),
          const SizedBox(height: 10),
          TextField(controller: _codeController, keyboardType: TextInputType.number, decoration: _decoration('6-digit room code')),
          const SizedBox(height: 12),
          SizedBox(height: 52, child: FilledButton(onPressed: _busy ? null : _joinRoom, style: FilledButton.styleFrom(backgroundColor: cyan, foregroundColor: bg), child: const Text('Join Room'))),
          const SizedBox(height: 16), _statusText(), const SizedBox(height: 24),
          const Text('Local music sharing test build • Playback sync is still being improved.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );

  Widget _roomScreen() => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Row(children: [
            const Icon(Icons.wifi, color: cyan), const SizedBox(width: 10),
            const Text('Party Room', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
            const Spacer(), TextButton(onPressed: _leaveRoom, child: const Text('Leave')),
          ]),
          const SizedBox(height: 18),
          _panel(child: Column(children: [
            const Text('ROOM CODE', style: TextStyle(color: Colors.white54, letterSpacing: 2)),
            const SizedBox(height: 8),
            Text(_roomCode, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold, letterSpacing: 5, color: cyan)),
            if (_role == 'Host') ...[
              const SizedBox(height: 12),
              const Text('GUESTS: connect to your phone hotspot', style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 6),
              SelectableText('Host IP: $_hostIp', style: const TextStyle(color: cyan, fontSize: 16)),
              const SelectableText('Port: $port', style: TextStyle(color: Colors.white54)),
            ],
          ])),
          const SizedBox(height: 16),
          _panel(child: Row(children: [
            const Icon(Icons.smartphone, color: purple, size: 28), const SizedBox(width: 12),
            const Expanded(child: Text('Connected phones')),
            Text('$_members / 10', style: const TextStyle(color: cyan, fontWeight: FontWeight.bold)),
          ])),
          const SizedBox(height: 16),
          _panel(child: Column(children: [
            const Icon(Icons.music_note, color: cyan, size: 54), const SizedBox(height: 8),
            Text(_trackName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            if (_role == 'Host')
              SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _loadingTrack ? null : _chooseTrack, icon: const Icon(Icons.library_music), label: Text(_loadingTrack ? 'Please wait...' : 'Choose Music File'))),
            if (_role == 'Guest' && _loadingTrack) const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _loadingTrack || _trackName == 'No song selected' ? null : _togglePlayback,
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              label: Text(_playing ? 'Pause' : 'Play'),
              style: FilledButton.styleFrom(backgroundColor: purple),
            ),
            const SizedBox(height: 8),
            Text(_playing ? 'PLAYING' : 'PAUSED', style: const TextStyle(color: cyan)),
            if (_role == 'Guest') const Text('The song is downloaded to this phone before playback.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          const SizedBox(height: 16), _statusText(), const SizedBox(height: 24),
          const Text('Playback currently starts on receipt of the command. Accurate cross-device timing is the next improvement.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38, fontSize: 11)),
        ],
      );

  Widget _panel({required Widget child}) => Container(width: double.infinity, padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(20)), child: child);
  InputDecoration _decoration(String hint) => InputDecoration(hintText: hint, filled: true, fillColor: panel, border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none));
  Widget _statusText() => Text(_status, textAlign: TextAlign.center, style: const TextStyle(color: cyan, fontSize: 12));
}
