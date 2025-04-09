import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../components/utils.dart';
import 'package:record/record.dart';
import 'dart:developer';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:intl/intl.dart';

// The recorded video plays correctly with the built-in player, but when played within the app using plugins, its orientation shifts to horizontal and appears blurry.
// Possible causes include the plugins wechat_camera_picker, video_player, and their underlying dependency, camera.
// After reimplementing using only the camera plugin, the issue persists, suggesting a high likelihood that the problem originates from the camera plugin itself.
// camere: ^0.11.1 solves this
// However, the media file stored in Gallery will be .temp extension

class AIChatScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AIChatScreen({
    Key? key,
    required this.userId,
    required this.userName,
  }) : super(key: key);

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _queryController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late VideoPlayerController? _videoPlayerController;

  // Add this to the state class
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  bool _isRecording = false;
  bool _isTyping = false;
  File? _selectedMedia;
  AssetType? _selectedMediaType;
  late String _emergencyType;
  final AudioRecorder _audioRecorder = AudioRecorder();
  bool _isProcessing = false;
  String? _recordedFilePath;

  // final String _apiUrl = 'http://10.0.2.2:5000'; // For emulator
  final String _apiUrl = "http://192.168.1.125:5000"; // For physical device

  @override
  void initState() {
    super.initState();
    usersCollection.doc(widget.userId).get().then((snapshot) {
      if (snapshot.exists) {
        setState(() {
          _emergencyType = snapshot.get('emergencyType') ?? "SOS";
        });
      }
    }).catchError((error) {
      log("Error fetching emergencyType: $error");
    });
    _loadChatHistory();
  }

  Future<void> _loadChatHistory() async {
    setState(() => _isLoading = true);

    try {
      // Get the chat history (20 messages) from Firestore
      QuerySnapshot querySnapshot = await usersCollection
          .doc(widget.userId)
          .collection('ai_chat_history')
          .orderBy('timestamp.user')
          .limit(20)
          .get();

      // Convert the QuerySnapshot to a List of Maps
      List<Map<String, dynamic>> messages = [];
      for (var doc in querySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;

        // Add the user's query
        messages.add({
          'role': "user",
          'text': data['query'],
          'timestamp': data['timestamp']["user"],
          'mediaType': data['mediaType'], // Add media type
          'mediaPath': data['mediaPath'], // Add media path
        });

        // Add the AI's response
        messages.add({
          'role': "model",
          'text': data['response'],
          'timestamp': data['timestamp']["model"],
        });

        // Get the latest session ID
      }

      // Reverse the messages to show oldest first
      // messages = messages.reversed.toList();

      setState(() {
        _messages = messages;
        _isLoading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });

      // Scroll to the bottom after loading
    } catch (e) {
      log('Error loading chat history: $e');
      setState(() => _isLoading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chat history: $e')),
      );
    }
  }

  Future<void> _sendQuery() async {
    if (_queryController.text.trim().isEmpty) return;

    final query = _queryController.text.trim();
    _queryController.clear();

    // Add the query to the UI immediately
    setState(() {
      _messages.add({
        'role': "user",
        'text': query,
        'timestamp': Timestamp.now(),
        'mediaType': 'text', // Add media type
        'mediaPath': null, // Add media path
      });
      _isProcessing = true;
    });

    // Scroll to the bottom immediately
    _scrollToBottom();

    try {
      // Send the query to the API
      final response = await http.post(
        Uri.parse('$_apiUrl/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'query': query,
          'chat_history': json.encode(_messages
              .map((message) =>
                  {'role': message['role'], 'text': message['text']})
              .toList()),
          'emergency_type': _emergencyType
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Add the AI's response to the UI
        setState(() {
          _messages.add({
            'role': "model",
            'text': data['response'],
            'timestamp': Timestamp.now(),
          });
          _isProcessing = false;
        });

        // Scroll to the bottom again
        _scrollToBottom();

        // Store the chat in Firestore
        await usersCollection
            .doc(widget.userId)
            .collection('ai_chat_history')
            .add({
          'query': query,
          'response': data['response'],
          'mediaType': 'text',
          'mediaPath': null,
          // Timestamp for query and response ---> second last and last messages
          'timestamp': {
            "user": _messages[_messages.length - 2]["timestamp"],
            "model": _messages[_messages.length - 1]["timestamp"]
          },
        });
      } else {
        // Handle API error
        setState(() {
          _messages.add({
            'role': "system",
            'text':
                'Sorry, I encountered an error processing your request. Please try again.',
            'timestamp': Timestamp.now(),
          });
          _isProcessing = false;
        });

        _scrollToBottom();

        log('API Error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      log('Error sending query: $e');

      // Show error message in the chat
      setState(() {
        _messages.add({
          'role': "system",
          'text':
              'Sorry, I encountered an error connecting to the server. Please check your internet connection and try again.',
          'timestamp': Timestamp.now(),
        });
        _isProcessing = false;
      });

      _scrollToBottom();
    }
    log(_messages.toString());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 100), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<String> _savePermanentMediaFile(
      File sourceFile, String mediaType) async {
    try {
      // Get application documents directory
      // final Directory appDocDir = await getApplicationDocumentsDirectory();
      Directory? externalDir = await getExternalStorageDirectory();

      // Create a media directory if it doesn't exist
      final Directory mediaDir =
          Directory('${externalDir!.path}/emergency_media');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      // Generate a unique filename based on timestamp and media type
      final String timestamp =
          DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final String extension = mediaType == 'image' ? 'jpg' : 'mp4';

      final String filename = '${mediaType}_${timestamp}.$extension';
      final String destinationPath = '${mediaDir.path}/$filename';

      // Copy file to permanent location
      final File destinationFile = await sourceFile.copy(destinationPath);

      log('Media saved permanently to: ${destinationFile.path}');
      return destinationFile.path;
    } catch (e) {
      log('Error saving permanent media file: $e');
      return sourceFile.path; // Fallback to original path if error
    }
  }

  void _playAudioRecording(String audioPath) async {
    // Case 1: Same audio is already playing - pause it
    if (_currentlyPlayingPath == audioPath && _isPlaying) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
      return;
    }

    // Case 2: Same audio is paused - resume it
    if (_currentlyPlayingPath == audioPath && !_isPlaying) {
      setState(() {
        _isPlaying = true;
      });
      await _audioPlayer.play();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Resuming audio...'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    // Case 3: Different audio or no audio playing - start new audio
    try {
      await _audioPlayer.setFilePath(audioPath);

      setState(() {
        _currentlyPlayingPath = audioPath;
        _isPlaying = true;
      });

      // Show playing toast
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Playing audio...'),
          duration: const Duration(seconds: 2),
        ),
      );
      await _audioPlayer.play();

      // Listen for completion
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          setState(() {
            _isPlaying = false;
            _currentlyPlayingPath = null;
          });
        }
      });
    } catch (e) {
      log('Error playing audio: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to play audio: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleVoiceRecording() {
    setState(() {
      _isRecording = !_isRecording;
    });

    if (_isRecording) {
      _startVoiceRecording();
    } else {
      _stopVoiceRecording();
    }
  }

  Future<void> _startVoiceRecording() async {
    try {
      // Check and request permission
      if (await _audioRecorder.hasPermission()) {
        // Get a valid storage directory
        Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cannot access external storage!')),
          );
          return;
        }

        // Define file path in external storage
        final String timestamp =
            DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final String filename = 'audio_${timestamp}.m4a';
        final Directory mediaDir =
            Directory('${externalDir.path}/emergency_media');

        final String filePath = '${mediaDir.path}/$filename';

        // Start recording in Raw 16-bit PCM at 16kHz (little-endian)
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc, // Raw 16-bit PCM
            sampleRate: 16000, // 16kHz
            numChannels: 1, // Mono
          ),
          path: filePath,
        );

        setState(() {
          _isRecording = true;
          _recordedFilePath = filePath;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording started...')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission denied')),
        );
      }
    } catch (e) {
      debugPrint('Error starting recording: $e');
    }
  }

  Future<void> _stopVoiceRecording() async {
    final query = _queryController.text.trim();
    _queryController.clear();
    try {
      final path = await _audioRecorder.stop();

      if (path != null) {
        setState(() {
          _messages.add({
            'role': "user",
            'text': "[Audio]${query.isNotEmpty ? ': $query' : ''}",
            'mediaType': 'audio',
            'mediaPath': path,
            'timestamp': Timestamp.now(),
          });
          _isProcessing = true;
          _isRecording = false;
          _recordedFilePath = path;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recording saved successfully')),
        );

        // Send the recording to the backend
        _sendAudioMessage(path, query);
      }
    } catch (e) {
      debugPrint('Error stopping recording: $e');
    }
  }

  // Uncomment the request part to call the actual API
  void _sendAudioMessage(String filePath, String query) async {
    try {
      var uri = Uri.parse("$_apiUrl/");

    var request = http.MultipartRequest("POST", uri)
      ..files.add(await http.MultipartFile.fromPath('audio', filePath,
          contentType: MediaType('audio', 'x-m4a')))
      ..fields['chat_history'] = json.encode(_messages
          .map(
              (message) => {'role': message['role'], 'text': message['text']})
          .toList())
      ..fields['emergency_type'] = _emergencyType
    ..fields['query'] = query;

      var response = await request.send();
      log("Audio response ${response.statusCode.toString()}");

      if (response.statusCode == 200) {
        String responseBody = await response.stream.bytesToString();
        var data = json.decode(responseBody);
    setState(() {
      _messages.add({
        'role': "model",
        'text': data["response"] ?? "I've processed your audio message. How can I help?",
        'timestamp': Timestamp.now(),
      });
      _isProcessing = false;
    });

    // Store in Firestore with the audio path
    await usersCollection.doc(widget.userId).collection('ai_chat_history').add({
      'query': "[Audio]:${data["transcription"]}\n[Query]${query.isNotEmpty ? ': $query' : ''}",
      'response': data["response"] ?? "I've processed your audio message. How can I help?",
      'mediaType': 'audio',
      'mediaPath': filePath,
      'timestamp': {
        "user": _messages[_messages.length - 2]["timestamp"],
        "model": _messages[_messages.length - 1]["timestamp"]
      },
    });
      } else {
        _handleApiError();
      }
    } catch (e) {
      _handleApiError();
    }

    _scrollToBottom();
  }

  void _openFullScreenMedia(String mediaType, String mediaPath) {
    final File mediaFile = File(mediaPath);

    if (!mediaFile.existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Media file no longer exists on device'),
        ),
      );
      return;
    }

    if (mediaType == 'image') {
      // Show image viewer
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Black background
              Container(color: Colors.black),

              // Image
              InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Center(
                  child: Image.file(
                    mediaFile,
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // Close button
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (mediaType == 'video') {
      // Initialize video controller
      final VideoPlayerController videoController =
          VideoPlayerController.file(mediaFile);

      // Create a future to handle initialization
      Future<void> initFuture = videoController.initialize();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Display video with FutureBuilder
                FutureBuilder(
                  future: initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      // Auto-play once initialized
                      videoController.play();

                      return Center(
                        child: AspectRatio(
                          aspectRatio: videoController.value.aspectRatio,
                          child: VideoPlayer(videoController),
                        ),
                      );
                    } else if (snapshot.hasError) {
                      // Handle error
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.red, size: 48),
                            SizedBox(height: 16),
                            Text(
                              "Error loading video: ${snapshot.error}",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    } else {
                      // Show loading
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 16),
                            Text(
                              "Loading video...",
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      );
                    }
                  },
                ),

                // Play/pause button overlay
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      if (videoController.value.isInitialized) {
                        if (videoController.value.isPlaying) {
                          videoController.pause();
                        } else {
                          videoController.play();
                        }
                      }
                    },
                  ),
                ),

                // Video controls - play button when paused
                FutureBuilder(
                  future: initFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.done) {
                      return ValueListenableBuilder<VideoPlayerValue>(
                          valueListenable: videoController,
                          builder: (context, value, child) {
                            return Visibility(
                              visible: !value.isPlaying,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 50,
                                  ),
                                ),
                              ),
                            );
                          });
                    }
                    return Container();
                  },
                ),

                // Close button
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                    onPressed: () {
                      videoController.pause();
                      videoController.dispose();
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openCameraPicker() async {
    try {
      final AssetEntity? entity = await CameraPicker.pickFromCamera(
        context,
        pickerConfig: const CameraPickerConfig(
          enableRecording: true,
          enableAudio: true,
        ),
      );

      if (entity == null) {
        return;
      }

      // Get the file from the entity
      final File? mediaFile = await entity.file;
      if (mediaFile != null) {
        setState(() {
          _selectedMedia = mediaFile;
          _selectedMediaType = entity.type;
          // Set isTyping to true to show send button
          _isTyping = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to process media')),
        );
      }
    } catch (e) {
      log('Error picking media: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture media: $e')),
      );
    }
  }

  void _sendMediaWithQuery() async {
    if (_selectedMedia == null) return;

    final query = _queryController.text.trim();
    _queryController.clear();

    // Add the media message to UI
    setState(() {
      _messages.add({
        'role': "user",
        'text': _selectedMediaType == AssetType.video
            ? "[Video]${query.isNotEmpty ? ': $query' : ''}"
            : "[Image]${query.isNotEmpty ? ': $query' : ''}",
        'mediaType': _selectedMediaType == AssetType.video ? 'video' : 'image',
        'mediaPath': _selectedMedia!.path,
        'timestamp': Timestamp.now(),
      });
      _isProcessing = true;
      // Clear selected media

      _isTyping = false;
    });

    _scrollToBottom();
    log(_selectedMedia.toString());
    log(_selectedMediaType.toString());

    var tempSelectedMedia = _selectedMedia;
    var tempSelectedMediaType = _selectedMediaType;
    setState(() {
      _selectedMedia = null;
      _selectedMediaType = null;
    });
    // Process the media as before
    await _sendMediaMessage(tempSelectedMedia!, tempSelectedMediaType!, query);
  }

  // Uncomment the request part to call the actual API
  Future<void> _sendMediaMessage(
      File mediaFile, AssetType type, String query) async {
    final String permanentPath = await _savePermanentMediaFile(
        mediaFile, type == AssetType.video ? 'video' : 'image');

    try {
      String contentType = type == AssetType.video ? 'video/mp4' : 'image/jpeg';
      String fieldName = type == AssetType.video ? 'video' : 'image';

    // Create multipart request
    var request = http.MultipartRequest('POST', Uri.parse('$_apiUrl/'))
      ..files.add(await http.MultipartFile.fromPath(
        fieldName,
        mediaFile.path, // Use original path for upload
        contentType: MediaType.parse(contentType),
      ))
      ..fields['emergency_type'] = _emergencyType
      ..fields['chat_history'] = json.encode(_messages
          .map(
              (message) => {'role': message['role'], 'text': message['text']})
          .toList())
      ..fields['query'] = query;

    log(request.toString());
    var response = await request.send();

    if (response.statusCode == 200) {
    String responseBody = await response.stream.bytesToString();
    var data = json.decode(responseBody);

    // Update UI with response
    setState(() {
      // Update the last message (user message) with the permanent path
      _messages[_messages.length - 1]['mediaPath'] = permanentPath;

      // Add the AI response
      _messages.add({
        'role': "model",
        'text': data["response"] ??
            "I've analyzed your ${type == AssetType.video ? 'video' : 'image'}. How can I help?",
        'timestamp': Timestamp.now(),
      });
      _isProcessing = false;
    });

    // Store in Firestore
    await usersCollection.doc(widget.userId).collection('ai_chat_history').add({
      'query': type == AssetType.video ? "[Video]:${data["transcription"]}\n[Query]${query.isNotEmpty ? ': $query' : ''}" : "[Image]:${data["transcription"]}\n[Query]${query.isNotEmpty ? ': $query' : ''}",
      'response': data["response"] ??
          "I've analyzed your ${type == AssetType.video ? 'video' : 'image'}. How can I help?",
      'mediaType': type == AssetType.video ? 'video' : 'image',
      'mediaPath': permanentPath, // Store permanent path
      'timestamp': {
        "user": _messages[_messages.length - 2]["timestamp"],
        "model": _messages[_messages.length - 1]["timestamp"]
      },
    });
      } else {
        _handleApiError();
      }
    } catch (e) {
      log('Error sending media: $e');
      _handleApiError();
    }

    _scrollToBottom();
  }

  void _showFullScreenPreview() {
    if (_selectedMedia == null) return;

    // Initialize video controller if it's a video
    if (_selectedMediaType == AssetType.video) {
      _videoPlayerController = VideoPlayerController.file(_selectedMedia!);

      // Create a future to handle the initialization
      Future<void> initializeVideoPlayerFuture =
          _videoPlayerController!.initialize();

      // Show loading indicator until video is ready
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => Dialog.fullscreen(
          child: Container(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Display the media with FutureBuilder to handle loading state
                _selectedMediaType == AssetType.video
                    ? FutureBuilder(
                        future: initializeVideoPlayerFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.done) {
                            // Once initialized, play the video and show the player
                            _videoPlayerController!.play();

                            return Center(
                              child: AspectRatio(
                                // Use the controller's aspect ratio, but constrain it to the screen
                                aspectRatio:
                                    _videoPlayerController!.value.aspectRatio,
                                child: VideoPlayer(_videoPlayerController!),
                              ),
                            );
                          } else if (snapshot.hasError) {
                            // Handle error case
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline,
                                      color: Colors.red, size: 48),
                                  SizedBox(height: 16),
                                  Text(
                                    "Error loading video: ${snapshot.error}",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            );
                          } else {
                            // Show loading indicator
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircularProgressIndicator(
                                      color: Colors.white),
                                  SizedBox(height: 16),
                                  Text(
                                    "Loading video...",
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ],
                              ),
                            );
                          }
                        },
                      )
                    : Image.file(
                        _selectedMedia!,
                        fit: BoxFit.contain,
                      ),

                // Video controls overlay (only show for videos when initialized)
                if (_selectedMediaType == AssetType.video)
                  Positioned.fill(
                    child: GestureDetector(
                      onTap: () {
                        if (_videoPlayerController != null &&
                            _videoPlayerController!.value.isInitialized) {
                          setState(() {
                            if (_videoPlayerController!.value.isPlaying) {
                              _videoPlayerController!.pause();
                            } else {
                              _videoPlayerController!.play();
                            }
                          });
                        }
                      },
                      child: Container(
                        color: Colors.transparent,
                      ),
                    ),
                  ),

                // Video play/pause button (only show when initialized and paused)
                if (_selectedMediaType == AssetType.video)
                  FutureBuilder(
                    future: initializeVideoPlayerFuture,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.done &&
                          !_videoPlayerController!.value.isPlaying) {
                        return Center(
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 50,
                            ),
                          ),
                        );
                      }
                      return Container();
                    },
                  ),

                // Close button
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                    onPressed: () {
                      // Dispose of the video controller when closing
                      if (_selectedMediaType == AssetType.video &&
                          _videoPlayerController != null) {
                        _videoPlayerController!.pause();
                        _videoPlayerController!.dispose();
                        _videoPlayerController = null;
                      }
                      Navigator.pop(dialogContext);
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      // For images, just show the image viewer
      showDialog(
        context: context,
        builder: (context) => Dialog.fullscreen(
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                _selectedMedia!,
                fit: BoxFit.contain,
              ),
              // Close button
              Positioned(
                top: 40,
                right: 20,
                child: IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, color: Colors.white),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildMediaPreview(String mediaType, String mediaPath) {
    if (mediaPath.isEmpty) {
      return const SizedBox.shrink();
    }

    final File mediaFile = File(mediaPath);
    if (!mediaFile.existsSync()) {
      return Container(
        padding: const EdgeInsets.all(8),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Row(
          children: [
            Icon(Icons.error, color: Colors.red, size: 16),
            SizedBox(width: 4),
            Expanded(
              child: Text(
                "Media file no longer available",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ],
        ),
      );
    }

    switch (mediaType) {
      case 'image':
        return GestureDetector(
          onTap: () => _openFullScreenMedia(mediaType, mediaPath),
          child: Container(
            constraints: const BoxConstraints(
              maxHeight: 150,
              maxWidth: 200,
            ),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                mediaFile,
                fit: BoxFit.cover,
              ),
            ),
          ),
        );

      case 'video':
        return GestureDetector(
          onTap: () => _openFullScreenMedia(mediaType, mediaPath),
          child: Container(
            width: 200,
            height: 120,
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: Icon(
                    Icons.play_circle_fill,
                    size: 50,
                    color: Colors.white.withOpacity(0.8),
                  ),
                ),
                Positioned(
                  bottom: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.play_arrow,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Play video',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case 'audio':
        return GestureDetector(
          onTap: () => _playAudioRecording(mediaPath),
          child: Container(
            width: 200,
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(
              vertical: 12,
              horizontal: 16,
            ),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentlyPlayingPath == mediaPath && _isPlaying
                      ? Icons
                          .pause_circle_outline // Show pause icon when this audio is playing
                      : Icons
                          .play_circle_outline, // Show play icon when audio is not playing
                  color: Colors.blue,
                  size: 24,
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Voice Message",
                    style: TextStyle(
                      color: Colors.black87,
                    ),
                  ),
                ),
                Icon(
                  Icons.headphones,
                  color: Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildWeChatBottomBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, -2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.1),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Show media preview if available
            if (_selectedMedia != null)
              GestureDetector(
                onTap: _showFullScreenPreview,
                child: Container(
                  height: 80, // Smaller height
                  width: 120, // Control width
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius:
                            BorderRadius.circular(11), // To fit inside border
                        child: Center(
                          child: _selectedMediaType == AssetType.video
                              ? Stack(
                                  alignment: Alignment.center,
                                  fit: StackFit.expand,
                                  children: [
                                    Container(color: Colors.black),
                                    Icon(Icons.play_circle_fill,
                                        color: Colors.white, size: 30),
                                  ],
                                )
                              : Image.file(
                                  _selectedMedia!,
                                  fit: BoxFit.cover,
                                  width: double.infinity,
                                  height: double.infinity,
                                ),
                        ),
                      ),
                      Positioned(
                        top: 5,
                        right: 5,
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedMedia = null;
                              _selectedMediaType = null;
                              if (_queryController.text.isEmpty) {
                                _isTyping = false;
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                      // Add tap indicator
                      Positioned(
                        bottom: 5,
                        left: 5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.touch_app,
                                  color: Colors.white, size: 12),
                              const SizedBox(width: 2),
                              Text(
                                "Tap to view",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // Input row
            Row(
              children: [
                // Voice recording button
                Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.red : Colors.grey.shade700,
                    ),
                    onPressed: _toggleVoiceRecording,
                  ),
                ),
                const SizedBox(width: 8),

                // Text input field
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _queryController,
                            decoration: InputDecoration(
                              hintText: _isRecording
                                  ? 'Recording... Press to stop'
                                  : _selectedMedia != null
                                      ? 'Add a message with your ${_selectedMediaType == AssetType.video ? 'video' : 'image'}...'
                                      : 'Type your emergency question...',
                              hintStyle: TextStyle(color: Colors.grey.shade600),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                            ),
                            enabled: !_isRecording,
                            textCapitalization: TextCapitalization.sentences,
                            onChanged: (text) {
                              setState(() {
                                _isTyping =
                                    text.isNotEmpty || _selectedMedia != null;
                              });
                            },
                            onSubmitted: (_) => _selectedMedia != null
                                ? _sendMediaWithQuery()
                                : _sendQuery(),
                          ),
                        ),
                        // Camera picker button (hide if media is selected)
                        if (_selectedMedia == null)
                          IconButton(
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.grey),
                            onPressed: _openCameraPicker,
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Send button or Emergency call button
                _isTyping
                    ? Material(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _selectedMedia != null
                              ? _sendMediaWithQuery
                              : _sendQuery,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            child: const Icon(
                              Icons.send,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      )
                    : Material(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: _callEmergencyServices,
                          child: Container(
                            padding: const EdgeInsets.all(10),
                            child: const Icon(
                              Icons.phone,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    final role = messageData['role'] as String;
    final messageText = messageData['text'] as String;
    final timestamp = messageData['timestamp'] as Timestamp?;
    final mediaType = messageData['mediaType'] as String?;
    final mediaPath = messageData['mediaPath'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            (role == "user") ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (role == "model")
            CircleAvatar(
              backgroundColor: Colors.red,
              radius: 18,
              child: const Icon(
                Icons.medical_services,
                color: Colors.white,
                size: 20,
              ),
            ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (role == "user")
                    ? Colors.blue.shade100
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Display media content if available
                  if (mediaType != null && mediaPath != null)
                    _buildMediaPreview(mediaType, mediaPath),

                  Text(
                    mediaType != 'audio' ? messageText : "",
                    style: TextStyle(
                      fontWeight:
                          (role == "model") && _isUrgentMessage(messageText)
                              ? FontWeight.bold
                              : FontWeight.normal,
                    ),
                  ),
                  mediaType != 'audio'
                      ? const SizedBox(height: 6)
                      : const SizedBox(
                          height: 0,
                        ),
                  Text(
                    formatTimestamp(timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleApiError() {
    setState(() {
      _messages.add({
        'role': "system",
        'text':
            'Sorry, I encountered an error processing your request. Please try again.',
        'timestamp': Timestamp.now(),
      });
      _isProcessing = false;
    });
  }

  void _clearChatAndMedia() async {
    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'Are you sure you want to clear all chat history? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);

              // Show loading indicator
              setState(() {
                _isLoading = true;
              });

              try {
                // 1. Get all chat records to find media paths
                QuerySnapshot chatSnapshot = await usersCollection
                    .doc(widget.userId)
                    .collection('ai_chat_history')
                    .get();

                // 2. Extract all media paths from chat records
                List<String> mediaPaths = [];
                for (var doc in chatSnapshot.docs) {
                  final data = doc.data() as Map<String, dynamic>;
                  if (data['mediaPath'] != null &&
                      data['mediaType'] != 'text') {
                    mediaPaths.add(data['mediaPath']);
                  }
                }

                // 3. Delete all media files from device storage
                for (String path in mediaPaths) {
                  final File mediaFile = File(path);
                  if (await mediaFile.exists()) {
                    await mediaFile.delete();
                    log('Deleted media file: $path');
                  }
                }

                // 4. Delete all chat records from Firestore
                for (var doc in chatSnapshot.docs) {
                  await doc.reference.delete();
                }

                // 5. Clear messages in the UI
                setState(() {
                  _messages = [];
                  _isLoading = false;
                });

                // Show success message
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content:
                          Text('Chat history and media cleared successfully')),
                );
              } catch (e) {
                log('Error clearing chat and media: $e');
                setState(() {
                  _isLoading = false;
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error clearing chat history: $e')),
                );
              }
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Emergency AI Assistant'),
            Text(
              'Get emergency information and assistance',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red, // Changed to red for emergency context
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _clearChatAndMedia,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Emergency warning banner
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.red.shade50,
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade700),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                            ),
                            children: const [
                              TextSpan(
                                text: "EMERGENCY DISCLAIMER: ",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text:
                                    "For life-threatening emergencies, call emergency services immediately (911/112/999). This AI provides guidance only.",
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Messages list
                Expanded(
                  child: GestureDetector(
                    onTap: () => FocusScope.of(context).unfocus(),
                    child: _messages.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.health_and_safety,
                                    size: 48, color: Colors.red),
                                const SizedBox(height: 16),
                                const Text(
                                  "Ask for emergency procedures, first aid instructions,\nor immediate safety information",
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 15,
                            ),
                            itemCount: _messages.length,
                            itemBuilder: (context, index) {
                              final messageData = _messages[index];
                              return _buildMessageBubble(messageData);
                            },
                          ),
                  ),
                ),

                // Loading indicator for processing
                if (_isProcessing)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.red.shade300),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Processing emergency request...',
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 14,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),

                // Emergency quick actions
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.grey.shade100,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildQuickAction(Icons.local_hospital, "CPR Steps"),
                        _buildQuickAction(Icons.healing, "Stop Bleeding"),
                        _buildQuickAction(Icons.warning, "Choking help"),
                        _buildQuickAction(
                            Icons.local_fire_department, "Fire Safety"),
                        _buildQuickAction(Icons.coronavirus, "Heart Attack"),
                        _buildQuickAction(Icons.security, "Emergency Shelter"),
                      ],
                    ),
                  ),
                ),
                _buildWeChatBottomBar()
              ],
            ),
    );
  }

  // Helper method to identify urgent messages for highlighting
  bool _isUrgentMessage(String message) {
    final urgentKeywords = [
      'emergency',
      'urgent',
      'immediately',
      'danger',
      'critical',
      'severe',
      'life-threatening',
      'call 911',
      'call emergency',
      'warning',
      'evacuate',
      'serious injury',
      'bleeding',
      'choking',
      'unconscious',
      'not breathing',
      'heart attack',
      'stroke',
      'crime',
      'stalk'
    ];

    final lowercaseMessage = message.toLowerCase();
    return urgentKeywords.any((keyword) => lowercaseMessage.contains(keyword));
  }

  // Quick action button builder
  Widget _buildQuickAction(IconData icon, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            _queryController.text = label;
            _sendQuery();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.red.shade200),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.red),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Add a method to call emergency services
  void _callEmergencyServices() {
    // This would typically use the url_launcher package to make a phone call
    // For now, we'll just show a dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.phone_in_talk, color: Colors.red),
            SizedBox(width: 8),
            Text('Emergency Call'),
          ],
        ),
        content: Text(
          'This would initiate a call to emergency services. Remember to only call emergency services for genuine emergencies.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // In a real app, this would launch the phone dialer
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content:
                        Text('Emergency call feature would be triggered here')),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('Call Emergency Services'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _queryController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
