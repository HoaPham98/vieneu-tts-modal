import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:vieneu_tts/vieneu_tts.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const VieneuTtsExampleApp());
}

class VieneuTtsExampleApp extends StatelessWidget {
  const VieneuTtsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VieNeu TTS On-Device',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const TtsHomePage(),
    );
  }
}

class TtsHomePage extends StatefulWidget {
  const TtsHomePage({super.key});

  @override
  State<TtsHomePage> createState() => _TtsHomePageState();
}

class _TtsHomePageState extends State<TtsHomePage> {
  final TextEditingController _textController = TextEditingController(
    text:
        'Xin chào! Đây là ứng dụng thử nghiệm VieNeu TTS, chuyển văn bản tiếng Việt thành giọng nói chất lượng cao hoàn toàn offline ngay trên thiết bị.',
  );
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _isChecking = true;
  bool _isDownloading = false;
  bool _isInitializing = false;
  bool _isSynthesizing = false;
  bool _isPlaying = false;

  double _downloadProgress = 0.0;
  String _downloadLabel = '';
  String _statusMessage = 'Đang kiểm tra tài nguyên...';

  String? _modelPath;
  String? _dictPath;
  String _selectedVoice = 'minh_quan_pro';
  final double _speechSpeed = 1.0;

  Uint8List? _lastAudioBytes;
  int _lastSynthesisMs = 0;
  int _streamedChunks = 0;

  @override
  void initState() {
    super.initState();
    _checkResourceStatus();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<String> _getModelsDir() async {
    final docDir = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docDir.path, 'vieneu_models'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  Future<void> _checkResourceStatus() async {
    setState(() => _isChecking = true);
    try {
      final modelsDir = await _getModelsDir();
      final modelFile = File(p.join(modelsDir, 'vieneu-v3-turbo-q8_0.gguf'));
      final dictFile = File(p.join(modelsDir, 'sea_g2p.bin'));

      final hasModel = await modelFile.exists() && await modelFile.length() > 100 * 1024 * 1024;
      final hasDict = await dictFile.exists() && await dictFile.length() > 40 * 1024 * 1024;

      if (hasModel && hasDict) {
        _modelPath = modelFile.path;
        _dictPath = dictFile.path;
        setState(() {
          _statusMessage = 'Tài nguyên đã tải xong. Đang khởi tạo engine...';
        });
        await _initializeEngine();
      } else {
        setState(() {
          _statusMessage = 'Chưa tải model hoặc từ điển. Vui lòng tải để sử dụng offline.';
        });
      }
    } catch (e) {
      setState(() => _statusMessage = 'Lỗi kiểm tra tài nguyên: $e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  Future<void> _downloadResources() async {
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadLabel = 'Đang tải GGUF Model (188 MB)...';
    });

    try {
      final modelsDir = await _getModelsDir();

      final mPath = await VieneuTts.downloadModel(
        destinationDir: modelsDir,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress * 0.75;
              _downloadLabel =
                  'Đang tải Model GGUF: ${(progress * 100).toStringAsFixed(1)}% (188 MB)';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadLabel = 'Đang tải từ điển SEA-G2P (60 MB)...';
        });
      }

      final dPath = await VieneuTts.downloadDictionary(
        destinationDir: modelsDir,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _downloadProgress = 0.75 + (progress * 0.25);
              _downloadLabel =
                  'Đang tải Dictionary: ${(progress * 100).toStringAsFixed(1)}% (60 MB)';
            });
          }
        },
      );

      _modelPath = mPath;
      _dictPath = dPath;

      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
          _downloadLabel = 'Tải hoàn tất! Đang khởi tạo...';
        });
      }

      await _initializeEngine();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải dữ liệu: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _initializeEngine() async {
    if (_modelPath == null) return;
    setState(() => _isInitializing = true);
    try {
      await VieneuTts.init(
        modelPath: _modelPath!,
        dictPath: _dictPath,
      );
      if (mounted) {
        setState(() {
          _statusMessage = 'VieNeu TTS sẵn sàng hoạt động offline!';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _statusMessage = 'Lỗi khởi tạo engine: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<void> _synthesizeSpeech({bool isStreaming = false}) async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng nhập văn bản tiếng Việt.')),
      );
      return;
    }

    if (!VieneuTts.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Engine chưa được khởi tạo.')),
      );
      return;
    }

    setState(() {
      _isSynthesizing = true;
      _streamedChunks = 0;
    });

    final stopwatch = Stopwatch()..start();

    try {
      if (isStreaming) {
        final chunks = <int>[];
        await for (final chunk in VieneuTts.stream(
          text: text,
          voice: _selectedVoice,
          speed: _speechSpeed,
        )) {
          chunks.addAll(chunk);
          if (mounted) {
            setState(() {
              _streamedChunks++;
            });
          }
        }
        stopwatch.stop();
        _lastAudioBytes = Uint8List.fromList(chunks);
      } else {
        final audioBytes = await VieneuTts.synthesize(
          text: text,
          voice: _selectedVoice,
          speed: _speechSpeed,
        );
        stopwatch.stop();
        _lastAudioBytes = audioBytes;
      }

      _lastSynthesisMs = stopwatch.elapsedMilliseconds;

      if (_lastAudioBytes != null && _lastAudioBytes!.isNotEmpty) {
        await _playAudio(_lastAudioBytes!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tổng hợp giọng nói: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSynthesizing = false);
      }
    }
  }

  Future<void> _playAudio(Uint8List bytes) async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(BytesSource(bytes));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi phát âm thanh: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isReady = VieneuTts.isInitialized;

    return Scaffold(
      appBar: AppBar(
        title: const Text('VieNeu TTS (On-Device)'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Kiểm tra lại tài nguyên',
            onPressed: _isDownloading || _isInitializing || _isSynthesizing ? null : _checkResourceStatus,
          )
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Card
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              color: isReady ? Colors.green.shade50 : Colors.amber.shade50,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isReady ? Icons.check_circle : Icons.offline_bolt,
                          color: isReady ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isReady ? 'Offline Ready (Sẵn sàng)' : 'Trạng thái tài nguyên',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: isReady ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _statusMessage,
                      style: TextStyle(color: Colors.grey.shade800, fontSize: 13),
                    ),
                    if (_isInitializing) ...[
                      const SizedBox(height: 12),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 6),
                      const Text(
                        'Đang nạp mô hình vào bộ nhớ thiết bị...',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (_isDownloading) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(value: _downloadProgress),
                      const SizedBox(height: 6),
                      Text(
                        _downloadLabel,
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                      ),
                    ],
                    if (!isReady && !_isDownloading && !_isChecking) ...[
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.cloud_download),
                        label: const Text('Tải Model & Dictionary (~248 MB)'),
                        onPressed: _downloadResources,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Voice Selector Dropdown
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Chọn giọng đọc (25 preset có sẵn):',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _selectedVoice,
                      items: VieneuTts.availableVoices.map((voice) {
                        return DropdownMenuItem<String>(
                          value: voice.id,
                          child: Text(
                            voice.label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (newVoice) {
                        if (newVoice != null) {
                          setState(() => _selectedVoice = newVoice);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Text Input
            Card(
              elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Văn bản tiếng Việt:',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        TextButton(
                          onPressed: () => _textController.clear(),
                          child: const Text('Xóa', style: TextStyle(fontSize: 12)),
                        )
                      ],
                    ),
                    TextField(
                      controller: _textController,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        hintText: 'Nhập câu tiếng Việt cần đọc...',
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSynthesizing && _streamedChunks == 0
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.volume_up),
                    label: const Text('Đọc (WAV)'),
                    onPressed: !isReady || _isSynthesizing
                        ? null
                        : () => _synthesizeSpeech(isStreaming: false),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: _isSynthesizing && _streamedChunks > 0
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.stream),
                    label: Text(_streamedChunks > 0
                        ? 'Stream ($_streamedChunks)'
                        : 'Stream thời gian thực'),
                    onPressed: !isReady || _isSynthesizing
                        ? null
                        : () => _synthesizeSpeech(isStreaming: true),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Audio Player Controls & Metrics Card
            if (_lastAudioBytes != null) ...[
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton.filled(
                                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                                onPressed: () {
                                  if (_isPlaying) {
                                    _audioPlayer.pause();
                                  } else {
                                    _playAudio(_lastAudioBytes!);
                                  }
                                },
                              ),
                              const SizedBox(width: 8),
                              IconButton.outlined(
                                icon: const Icon(Icons.stop),
                                onPressed: () => _audioPlayer.stop(),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'Thời gian sinh: ${_lastSynthesisMs}ms',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              Text(
                                'Dung lượng: ${(_lastAudioBytes!.length / 1024).toStringAsFixed(1)} KB (48kHz)',
                                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                              ),
                            ],
                          )
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
