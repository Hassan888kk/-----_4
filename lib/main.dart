
import 'dart:convert';

import 'package:audio_service/audio_service.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio/just_audio.dart';

// ============================================================
// SRS MUSIC PLAYER
// ============================================================

late SrsAudioHandler audioHandler;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  audioHandler = await AudioService.init(
    builder: () => SrsAudioHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.srs.music.channel',
      androidNotificationChannelName: 'SRS Music Player',
      androidNotificationOngoing: false,
      androidStopForegroundOnPause: false,
    ),
  ) as SrsAudioHandler;

  runApp(const SrsApp());
}

// ============================================================
// AUDIO HANDLER: تشغيل الصوت في الخلفية
// ============================================================

class SrsAudioHandler extends BaseAudioHandler {
  final AudioPlayer player = AudioPlayer();
  List<MediaItem> songs = [];

  SrsAudioHandler() {
    player.playbackEventStream.listen((_) {
      _publishState();
    });

    player.currentIndexStream.listen((index) {
      if (index != null && index >= 0 && index < songs.length) {
        mediaItem.add(songs[index]);
      }
    });

    player.durationStream.listen((duration) {
      if (duration != null) {
        final index = player.currentIndex;
        if (index != null && index >= 0 && index < songs.length) {
          mediaItem.add(songs[index].copyWith(duration: duration));
        }
      }
    });
  }

  Future<void> loadSongs(List<SongModel> input) async {
    songs = input
        .where((song) => song.uri != null && song.uri!.isNotEmpty)
        .map(
          (song) => MediaItem(
            id: song.uri!,
            title: song.title.isEmpty ? 'Unknown song' : song.title,
            artist: song.artist ?? 'Unknown artist',
            album: song.album ?? 'Local music',
            duration: Duration(milliseconds: song.duration ?? 0),
          ),
        )
        .toList();

    queue.add(songs);

    if (songs.isEmpty) return;

    await player.setAudioSource(
      ConcatenatingAudioSource(
        children: songs
            .map(
              (song) => AudioSource.uri(Uri.parse(song.id)),
            )
            .toList(),
      ),
      initialIndex: 0,
    );

    mediaItem.add(songs.first);
    _publishState();
  }

  Future<void> playSongAt(int index) async {
    if (index < 0 || index >= songs.length) return;

    await player.seek(Duration.zero, index: index);
    await player.play();
  }

  @override
  Future<void> play() => player.play();

  @override
  Future<void> pause() => player.pause();

  @override
  Future<void> stop() async {
    await player.stop();
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => player.seek(position);

  @override
  Future<void> skipToNext() async {
    if (player.hasNext) await player.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    if (player.hasPrevious) {
      await player.seekToPrevious();
    } else {
      await player.seek(Duration.zero);
    }
  }

  void _publishState() {
    final playing = player.playing;
    final processing = player.processingState;

    playbackState.add(
      PlaybackState(
        controls: [
          if (player.hasPrevious)
            MediaControl.skipToPrevious,
          if (playing) MediaControl.pause else MediaControl.play,
          if (player.hasNext) MediaControl.skipToNext,
          MediaControl.stop,
        ],
        systemActions: const {
          MediaAction.seek,
        },
        androidCompactActionIndices: const [0, 1, 2],
        processingState: switch (processing) {
          ProcessingState.idle => AudioProcessingState.idle,
          ProcessingState.loading => AudioProcessingState.loading,
          ProcessingState.buffering => AudioProcessingState.buffering,
          ProcessingState.ready => AudioProcessingState.ready,
          ProcessingState.completed => AudioProcessingState.completed,
        },
        playing: playing,
        updatePosition: player.position,
        bufferedPosition: player.bufferedPosition,
        speed: player.speed,
        queueIndex: player.currentIndex,
      ),
    );
  }
}

// ============================================================
// APP + SETTINGS
// ============================================================

class SrsApp extends StatefulWidget {
  const SrsApp({super.key});

  @override
  State<SrsApp> createState() => _SrsAppState();
}

class _SrsAppState extends State<SrsApp> {
  String appName = 'SRS';
  bool darkMode = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) return;

    setState(() {
      appName = prefs.getString('app_name') ?? 'SRS';
      darkMode = prefs.getBool('dark_mode') ?? true;
    });
  }

  Future<void> _saveName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_name', name);

    if (mounted) setState(() => appName = name);
  }

  Future<void> _saveTheme(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', value);

    if (mounted) setState(() => darkMode = value);
  }

  @override
  Widget build(BuildContext context) {
    const bronze = Color(0xFFB68A55);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: appName,
      theme: ThemeData(
        useMaterial3: true,
        brightness: darkMode ? Brightness.dark : Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: bronze,
          brightness: darkMode ? Brightness.dark : Brightness.light,
        ),
        scaffoldBackgroundColor:
            darkMode ? const Color(0xFF151515) : const Color(0xFFF4F0E8),
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 0,
        ),
      ),
      home: HomePage(
        appName: appName,
        darkMode: darkMode,
        onNameChanged: _saveName,
        onThemeChanged: _saveTheme,
      ),
    );
  }
}

// ============================================================
// HOME PAGE
// ============================================================

class HomePage extends StatefulWidget {
  final String appName;
  final bool darkMode;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<bool> onThemeChanged;

  const HomePage({
    super.key,
    required this.appName,
    required this.darkMode,
    required this.onNameChanged,
    required this.onThemeChanged,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final OnAudioQuery audioQuery = OnAudioQuery();

  List<SongModel> songs = [];
  bool loading = false;
  String errorMessage = '';
  String searchText = '';
  int tabIndex = 0;
  String lyrics = '';
  String lyricsFileName = '';

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    setState(() {
      loading = true;
      errorMessage = '';
    });

    try {
      bool permitted = await audioQuery.permissionsStatus();

      if (!permitted) {
        permitted = await audioQuery.permissionsRequest();
      }

      if (!permitted) {
        setState(() {
          errorMessage = 'يجب السماح بالوصول إلى ملفات الموسيقى.';
          loading = false;
        });
        return;
      }

      final result = await audioQuery.querySongs();

      if (!mounted) return;

      setState(() {
        songs = result
            .where((song) => song.uri != null && song.uri!.isNotEmpty)
            .toList();
        loading = false;
      });

      await audioHandler.loadSongs(songs);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        errorMessage = 'تعذر قراءة الأغاني. تحقق من الصلاحيات.';
        loading = false;
      });
    }
  }

  Future<void> _pickLyrics() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;

      if (bytes == null) {
        _message('تعذر قراءة الملف المحدد.');
        return;
      }

      String content;

      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = latin1.decode(bytes);
      }

      if (!mounted) return;

      setState(() {
        lyrics = content;
        lyricsFileName = file.name;
      });

      setState(() => tabIndex = 1);
    } catch (_) {
      _message('حدث خطأ أثناء فتح ملف الكلمات.');
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '00:00';

    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds =
        (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final filteredSongs = songs.where((song) {
      final query = searchText.toLowerCase();

      return song.title.toLowerCase().contains(query) ||
          (song.artist ?? '').toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.appName,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: 4,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'إعادة فحص الأغاني',
            onPressed: _loadSongs,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: IndexedStack(
        index: tabIndex,
        children: [
          _buildLibrary(filteredSongs),
          _buildLyrics(),
          _buildSettings(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tabIndex,
        onDestinationSelected: (value) {
          setState(() => tabIndex = value);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_music_outlined),
            selectedIcon: Icon(Icons.library_music),
            label: 'الأغاني',
          ),
          NavigationDestination(
            icon: Icon(Icons.lyrics_outlined),
            selectedIcon: Icon(Icons.lyrics),
            label: 'الكلمات',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'الإعدادات',
          ),
        ],
      ),
      bottomSheet: _miniPlayer(),
    );
  }

  // ----------------------------------------------------------
  // MUSIC LIBRARY
  // ----------------------------------------------------------

  Widget _buildLibrary(List<SongModel> filteredSongs) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: TextField(
            onChanged: (value) {
              setState(() => searchText = value);
            },
            decoration: InputDecoration(
              hintText: 'ابحث عن أغنية أو فنان...',
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        if (loading)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else if (errorMessage.isNotEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(errorMessage, textAlign: TextAlign.center),
              ),
            ),
          )
        else if (filteredSongs.isEmpty)
          const Expanded(
            child: Center(
              child: Text('لا توجد أغنيات مطابقة.'),
            ),
          )
        else
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 100),
              itemCount: filteredSongs.length,
              itemBuilder: (context, index) {
                final song = filteredSongs[index];
                final originalIndex = songs.indexOf(song);

                return ListTile(
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.music_note),
                  ),
                  title: Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    song.artist ?? 'فنان غير معروف',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Text(
                    _formatDuration(
                      song.duration == null
                          ? null
                          : Duration(milliseconds: song.duration!),
                    ),
                  ),
                  onTap: () async {
                    try {
                      await audioHandler.playSongAt(originalIndex);
                    } catch (_) {
                      _message('تعذر تشغيل هذه الأغنية.');
                    }
                  },
                );
              },
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------
  // LYRICS
  // ----------------------------------------------------------

  Widget _buildLyrics() {
    final isArabic = RegExp(r'[\u0600-\u06FF]').hasMatch(lyrics);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'كلمات الأغنية',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            lyricsFileName.isEmpty
                ? 'افتح ملف كلمات بصيغة TXT من هاتفك.'
                : lyricsFileName,
            style: const TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _pickLyrics,
            icon: const Icon(Icons.file_open),
            label: const Text('اختيار ملف TXT'),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                border: Border.all(
                  color: Theme.of(context).dividerColor,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: lyrics.isEmpty
                  ? const Center(
                      child: Text(
                        'ستظهر الكلمات هنا بعد اختيار الملف.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : SingleChildScrollView(
                      child: SelectableText(
                        lyrics,
                        textDirection: isArabic
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 18,
                          height: 1.9,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------
  // SETTINGS
  // ----------------------------------------------------------

  Widget _buildSettings() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'إعدادات التطبيق',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        ListTile(
          leading: const Icon(Icons.edit_outlined),
          title: const Text('اسم المشغل'),
          subtitle: Text(widget.appName),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final controller = TextEditingController(
              text: widget.appName,
            );

            final name = await showDialog<String>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('تغيير اسم المشغل'),
                content: TextField(
                  controller: controller,
                  maxLength: 30,
                  decoration: const InputDecoration(
                    hintText: 'اكتب الاسم الجديد',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext),
                    child: const Text('إلغاء'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(
                      dialogContext,
                      controller.text.trim(),
                    ),
                    child: const Text('حفظ'),
                  ),
                ],
              ),
            );

            if (name != null && name.trim().isNotEmpty) {
              widget.onNameChanged(name.trim());
            }
          },
        ),
        const Divider(),
        SwitchListTile(
          secondary: const Icon(Icons.dark_mode_outlined),
          title: const Text('الوضع الداكن'),
          subtitle: const Text('التبديل بين المظهر الداكن والفاتح'),
          value: widget.darkMode,
          onChanged: widget.onThemeChanged,
        ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.translate),
          title: Text('لغات الكلمات'),
          subtitle: Text('العربية، الإنجليزية، الروسية، البرتغالية'),
        ),
        const ListTile(
          leading: Icon(Icons.offline_bolt_outlined),
          title: Text('التشغيل المحلي'),
          subtitle: Text(
            'الموسيقى والكلمات من ملفات الهاتف دون إنترنت.',
          ),
        ),
        const ListTile(
          leading: Icon(Icons.info_outline),
          title: Text('حول التطبيق'),
          subtitle: Text('SRS Music Player · الإصدار 1.0.0'),
        ),
      ],
    );
  }

  // ----------------------------------------------------------
  // MINI PLAYER
  // ----------------------------------------------------------

  Widget _miniPlayer() {
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: StreamBuilder<MediaItem?>(
          stream: audioHandler.mediaItem,
          builder: (context, snapshot) {
            final item = snapshot.data;

            return StreamBuilder<PlaybackState>(
              stream: audioHandler.playbackState,
              builder: (context, stateSnapshot) {
                final playing =
                    stateSnapshot.data?.playing ?? false;

                return Container(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: Row(
                    children: [
                      const Icon(Icons.album_outlined, size: 34),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              item?.title ?? 'اختر أغنية',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              item?.artist ?? 'SRS Music Player',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'السابق',
                        onPressed: () => audioHandler.skipToPrevious(),
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton.filled(
                        tooltip: playing ? 'إيقاف مؤقت' : 'تشغيل',
                        onPressed: () {
                          if (playing) {
                            audioHandler.pause();
                          } else {
                            audioHandler.play();
                          }
                        },
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      IconButton(
                        tooltip: 'التالي',
                        onPressed: () => audioHandler.skipToNext(),
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}