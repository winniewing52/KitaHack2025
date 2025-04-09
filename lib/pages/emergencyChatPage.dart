import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../components/utils.dart';
import 'dart:developer';
import 'dart:async';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:wechat_camera_picker/wechat_camera_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

class EmergencyGroupChatScreen extends StatefulWidget {
  final String currentUserId;
  final String emergencyUserId;
  final String emergencyUserName;
  final String emergencyType;

  const EmergencyGroupChatScreen({
    Key? key,
    required this.currentUserId,
    required this.emergencyUserId,
    required this.emergencyUserName,
    required this.emergencyType,
  }) : super(key: key);

  @override
  State<EmergencyGroupChatScreen> createState() =>
      _EmergencyGroupChatScreenState();
}

class _EmergencyGroupChatScreenState extends State<EmergencyGroupChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ScrollController _scrollController = ScrollController();
  String? _currentUserName;
  String? _currentUserRole;
  bool _isLoading = true;
  int _participantCount = 0;
  List<Map<String, dynamic>> _messages = [];
  StreamSubscription? _messageSubscription;
  StreamSubscription? _chatRoomSubscription;
  int _unreadMessagesCount = 0;
  int _unreadInfoCount = 0;
  Timestamp? _lastSeenTimestamp;

  // Chat room ID is now based only on the emergency user ID
  late String _chatRoomId;

  // Add new properties for media handling
  File? _selectedMedia;
  AssetType? _selectedMediaType;
  bool _isTyping = false;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentlyPlayingPath;
  bool _isPlaying = false;
  bool _isRecording = false;
  final AudioRecorder _audioRecorder = AudioRecorder();
  String? _recordedFilePath;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // Create chat room ID based only on emergency user ID to make it a group chat
    _chatRoomId = 'emergency_${widget.emergencyUserId}';
    _loadCurrentUserInfo().then((_) {
      _joinChatRoom();
      _setupMessageListener();
    });
    // Add this to scroll once view is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  void _setupMessageListener() {
    // Get last seen timestamp first
    _firestore
        .collection('emergency_group_chats')
        .doc(_chatRoomId)
        .get()
        .then((chatRoom) {
      
      if (chatRoom.exists) {
        final data = chatRoom.data() as Map<String, dynamic>;
        if (data['participantDetails'] != null &&
            data['participantDetails'][widget.currentUserId] != null) {
          _lastSeenTimestamp =
              data['participantDetails'][widget.currentUserId]['lastSeen'];
        }
      }

      // Now set up the message listener
      _messageSubscription = _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .orderBy('timestamp', descending: false)
          .snapshots()
          .listen((snapshot) {
        
        final messages = snapshot.docs.map((doc) => doc.data()).toList();

        // Calculate unread messages from other user
        int newUnreadCount = 0;
        if (_lastSeenTimestamp != null) {
          newUnreadCount = messages
              .where((msg) =>
                  msg['timestamp'] != null &&
                  (msg['timestamp'] as Timestamp)
                          .compareTo(_lastSeenTimestamp!) >
                      0 &&
                  msg['senderId'] != widget.currentUserId)
              .length;
        }
          setState(() {
            _messages = messages;
            _unreadMessagesCount = newUnreadCount;
          });


    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
      });
    });
  }

  Future<void> _loadCurrentUserInfo() async {
    try {
      DocumentSnapshot userDoc =
          await _firestore.collection('users').doc(widget.currentUserId).get();

      if (userDoc.exists) {
        final userData = userDoc.data() as Map<String, dynamic>;
        setState(() {
          _currentUserName = userData['username'] ?? 'Helper';

          _currentUserRole = widget.currentUserId == widget.emergencyUserId
              ? 'emergency'
              : 'helper';
          _isLoading = false;
        });
      } else {
        setState(() {
          _currentUserName = 'Helper';
          _currentUserRole = widget.currentUserId == widget.emergencyUserId
              ? 'emergency'
              : 'helper';
          _isLoading = false;
        });
      }
    } catch (e) {
      log('Error loading user info: $e');
      setState(() {
        _currentUserName = 'Helper';
        _currentUserRole = widget.currentUserId == widget.emergencyUserId
            ? 'emergency'
            : 'helper';
        _isLoading = false;
      });
    }
  }

  Future<void> _joinChatRoom() async {
    try {
      // Get or create chat room document
      DocumentReference chatRoomRef =
          _firestore.collection('emergency_group_chats').doc(_chatRoomId);

      // Check if the chat room exists
      DocumentSnapshot chatRoomSnapshot = await chatRoomRef.get();

      if (!chatRoomSnapshot.exists) {
        // Create new chat room if it doesn't exist
        await chatRoomRef.set({
          'emergencyUserId': widget.emergencyUserId,
          'emergencyUserName': widget.emergencyUserName,
          'emergencyType': widget.emergencyType,
          'createdAt': FieldValue.serverTimestamp(),
          'participants': [widget.currentUserId],
          'participantDetails': {
            widget.currentUserId: {
              'name': _currentUserName,
              'role': _currentUserRole,
              'joinedAt': FieldValue.serverTimestamp(),
              'lastSeen': FieldValue.serverTimestamp(),
            },
          },
          'lastMessage': 'Chat started',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'messageCount': 0,
        });

        // Add system message that chat has been created
        await _addSystemMessage(
          'Emergency chat room created. Please coordinate help here.',
        );
      } else {
        // Chat room exists, add current user to participants if not already present
        Map<String, dynamic> data =
            chatRoomSnapshot.data() as Map<String, dynamic>;
        List<dynamic> participants = data['participants'] ?? [];

        if (!participants.contains(widget.currentUserId)) {
          await chatRoomRef.update({
            'participants': FieldValue.arrayUnion([widget.currentUserId]),
            'participantDetails.${widget.currentUserId}': {
              'name': _currentUserName,
              'role': _currentUserRole,
              'joinedAt': FieldValue.serverTimestamp(),
              'lastSeen': FieldValue.serverTimestamp(),
            },
          });

          // Add system message that new user has joined
          await _addSystemMessage(
            '${_currentUserName} joined the emergency chat.',
          );
        } else {
          // Just update last seen
          await chatRoomRef.update({
            'participantDetails.${widget.currentUserId}.lastSeen':
                FieldValue.serverTimestamp(),
          });
        }
      }

      // Set up listener for participants count and other info
      _chatRoomSubscription = chatRoomRef.snapshots().listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data() as Map<String, dynamic>;
          final participants = data['participants'] as List<dynamic>;
          setState(() {
            _participantCount = participants.length;
            // Reset unread info count when info panel is opened
            if (_unreadInfoCount > 0) {
              _updateLastSeen();
              _unreadInfoCount = 0;
            }
          });
        }
      });
    } catch (e) {
      log('Error joining chat room: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to join emergency chat. Please try again.'),
        ),
      );
    }
  }

  Future<void> _addSystemMessage(String message) async {
    try {
      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add({
        'text': message,
        'senderId': 'system',
        'senderName': 'System',
        'senderRole': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'system',
      });

      // Update last message in chat room
      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .update({
        'lastMessage': message,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'messageCount': FieldValue.increment(1),
      });
    } catch (e) {
      log('Error adding system message: $e');
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    final messageData = {
      'text': messageText,
      'senderId': widget.currentUserId,
      'senderName': _currentUserName,
      'senderRole': _currentUserRole,
      'timestamp': Timestamp.now(), // Use local timestamp first
      'type': 'message',
    };

    setState(() {
      _messages.add(messageData);
    });

    // Scroll immediately
    _scrollToBottom();

    try {
      // Add message to Firestore
      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add(messageData);

      // Update last message in chat room document
      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .update({
        'lastMessage': messageText,
        'lastMessageTime': FieldValue.serverTimestamp(),
        'messageCount': FieldValue.increment(1),
        'participantDetails.${widget.currentUserId}.lastSeen':
            FieldValue.serverTimestamp(),
      });

      // Update our last seen timestamp
      _lastSeenTimestamp = messageData['timestamp'] as Timestamp;

      // Reset unread message count since we're fully caught up
      setState(() {
        _unreadMessagesCount = 0;
      });
    } catch (e) {
      log('Error sending message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to send message. Please try again.'),
        ),
      );
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _updateLastSeen() async {
    try {
      final now = Timestamp.now();
      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .update({
        'participantDetails.${widget.currentUserId}.lastSeen': now,
      });

      // Update local last seen timestamp
      _lastSeenTimestamp = now;

      // Reset unread counts
      setState(() {
        _unreadMessagesCount = 0;
        _unreadInfoCount = 0;
      });
    } catch (e) {
      log('Error updating last seen: $e');
    }
  }

  Color _getSenderColor(String role) {
    switch (role) {
      case 'emergency':
        return Colors.red.shade700;
      case 'helper':
        return Colors.blue.shade700;
      case 'system':
        return Colors.grey.shade700;
      default:
        return Colors.grey.shade700;
    }
  }

  Future<Map<String, String>> _uploadMediaToStorage(File file, String mediaType) async {
    try {
      // First ensure the storage directory exists
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        throw Exception('Cannot access external storage');
      }

      // Create emergency chat media directory
      final Directory mediaDir = Directory('${externalDir.path}/emergency_chats/${widget.emergencyUserId}');
      if (!await mediaDir.exists()) {
        await mediaDir.create(recursive: true);
      }

      String fileName = '${DateTime.now().millisecondsSinceEpoch}_$mediaType${path.extension(file.path)}';
      String storagePath = '${mediaDir.path}/$fileName';
      String firebasePath = 'emergency_chats/${widget.emergencyUserId}/$fileName';
      
      // Copy the file to our app's storage directory
      final File storedFile = await file.copy(storagePath);
      
      final ref = _storage.ref().child(firebasePath);
      final uploadTask = ref.putFile(storedFile);
      
      // Show upload progress
      uploadTask.snapshotEvents.listen((TaskSnapshot snapshot) {
        final progress = (snapshot.bytesTransferred / snapshot.totalBytes) * 100;
        log('Upload progress: $progress%');
      });

      final snapshot = await uploadTask.whenComplete(() {});
      final downloadUrl = await snapshot.ref.getDownloadURL();
      
      log('Media uploaded successfully: $downloadUrl');
      return {
        'localPath': storagePath,
        'downloadUrl': downloadUrl
      };
    } catch (e) {
      log('Error uploading media: $e');
      throw Exception('Failed to upload media: $e');
    }
  }

  // Havent complete should retreive from firebase
  Future<void> cleanupLocalMedia() async {
    try {
      final Directory? externalDir = await getExternalStorageDirectory();
      if (externalDir == null) return;

      final Directory mediaDir = Directory('${externalDir.path}/emergency_chats/${widget.emergencyUserId}');
      if (await mediaDir.exists()) {
        // Get all files in directory
        final List<FileSystemEntity> files = await mediaDir.list().toList();
        
        // Check each file against active messages
        for (var file in files) {
          if (file is File) {
            bool isActive = _messages.any((message) => 
              message['localPath'] == file.path && 
              message['mediaUrl'] != null
            );
            
            if (!isActive) {
              await file.delete();
              log('Deleted inactive media file: ${file.path}');
            }
          }
        }
      }
    } catch (e) {
      log('Error cleaning up local media: $e');
    }
  }

  void _sendMediaMessage() async {
    if (_selectedMedia == null) return;

    final query = _messageController.text.trim();
    _messageController.clear();

    try {
      setState(() => _isProcessing = true);

      final mediaType = _selectedMediaType == AssetType.video ? 'video' : 'image';
      final mediaUrls = await _uploadMediaToStorage(_selectedMedia!, mediaType);

      final messageData = {
        'text': '[$mediaType]${query.isNotEmpty ? ': $query' : ''}',
        'senderId': widget.currentUserId,
        'senderName': _currentUserName,
        'senderRole': _currentUserRole,
        'timestamp': Timestamp.now(),
        'type': 'message',
        'mediaType': mediaType,
        'mediaUrl': mediaUrls['downloadUrl'],
        'localPath': mediaUrls['localPath'],
      };

      setState(() {
        _messages.add(messageData);
        _selectedMedia = null;
        _selectedMediaType = null;
        _isTyping = false;
        _isProcessing = false;
      });

      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .collection('messages')
          .add(messageData);

      await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .update({
        'lastMessage': messageData['text'],
        'lastMessageTime': FieldValue.serverTimestamp(),
        'messageCount': FieldValue.increment(1),
      });

      _scrollToBottom();
    } catch (e) {
      setState(() => _isProcessing = false);
      log('Error sending media message: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send media message: $e')),
      );
    }
  }

  static Future<void> cleanupEmergencyMedia(String emergencyUserId) async {
    try {
      final storage = FirebaseStorage.instance;
      final ref = storage.ref().child('emergency_chats/$emergencyUserId');
      
      final ListResult result = await ref.listAll();
      
      // Delete all files in the emergency user's folder
      for (var item in result.items) {
        await item.delete();
      }
      
      log('Cleaned up media for emergency: $emergencyUserId');
    } catch (e) {
      log('Error cleaning up media: $e');
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
      if (entity == null) return;

      final File? mediaFile = await entity.file;
      if (mediaFile != null) {
        setState(() {
          _selectedMedia = mediaFile;
          _selectedMediaType = entity.type;
          _isTyping = true;
        });
      }
    } catch (e) {
      log('Error picking media: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to capture media: $e')),
      );
    }
  }

  Widget _buildMessageBubble(Map<String, dynamic> messageData) {
    final isMe = messageData['senderId'] == widget.currentUserId;
    final messageText = messageData['text'] as String;
    final senderName = messageData['senderName'] as String? ?? 'Unknown';
    final senderRole = messageData['senderRole'] as String? ?? 'helper';
    final timestamp = messageData['timestamp'] as Timestamp?;
    final mediaType = messageData['mediaType'] as String?;
    final mediaUrl = messageData['mediaUrl'] as String?;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: _getSenderColor(senderRole),
              child: senderRole == 'emergency'
                  ? const Icon(Icons.warning, color: Colors.white, size: 18)
                  : Text(
                      senderName.isNotEmpty ? senderName[0].toUpperCase() : '?',
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: mediaUrl != null
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade100 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe) _buildSenderInfo(senderName, senderRole),
                  
                  if (mediaUrl != null)
                    _buildMediaContent(mediaType!, mediaUrl),
                  
                  if (!messageText.startsWith('[Image]') && 
                      !messageText.startsWith('[Video]'))
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(messageText),
                    ),
                  
                  Padding(
                    padding: const EdgeInsets.only(top: 4, right: 8),
                    child: Text(
                      formatTimestamp(timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isMe) const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildSenderInfo(String senderName, String senderRole) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 8, right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            senderName,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: _getSenderColor(senderRole),
            ),
          ),
          if (senderRole == 'emergency') ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Emergency User',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.red.shade900,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMediaContent(String mediaType, String mediaUrl) {
    log(mediaUrl);
    // Try to load from Firebase URL first, fallback to local path if needed
    switch (mediaType) {
      case 'image':
        return GestureDetector(
          onTap: () => _showFullScreenImage(mediaUrl),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 280, maxHeight: 200),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                mediaUrl.startsWith('http') ? mediaUrl : 'file://$mediaUrl',
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return _buildMediaLoadingIndicator();
                },
                errorBuilder: (context, error, stackTrace) {
                  log('Error loading image: $error');
                  return Container(
                    padding: const EdgeInsets.all(8),
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.error_outline, color: Colors.red),
                  );
                },
              ),
            ),
          ),
        );

      case 'video':
        return GestureDetector(
          onTap: () => _showFullScreenVideo(mediaUrl),
          child: Container(
            width: 200,
            height: 150,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.play_circle_fill,
                  size: 50,
                  color: Colors.white.withOpacity(0.8),
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
                        Icon(Icons.play_arrow, color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Play video',
                          style: TextStyle(color: Colors.white, fontSize: 10),
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
          onTap: () => _playAudioRecording(mediaUrl),
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
                  _currentlyPlayingPath == mediaUrl && _isPlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  color: Colors.blue,
                  size: 24,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Voice Message",
                    style: TextStyle(
                      color: Colors.black87,
                    ),
                  ),
                ),
                const Icon(
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

  Widget _buildMediaLoadingIndicator() {
    return Container(
      height: 150,
      width: 200,
      color: Colors.grey.shade200,
      child: const Center(child: CircularProgressIndicator()),
    );
  }

  void _showFullScreenImage(String imageUrl) {
    log(imageUrl);
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(color: Colors.black),
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 3.0,
              child: Center(
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return _buildMediaLoadingIndicator();
                  },
                ),
              ),
            ),
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

  void _showFullScreenVideo(String videoUrl) {
    final VideoPlayerController videoController =
        VideoPlayerController.networkUrl(Uri.parse(videoUrl));

    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FutureBuilder(
                future: videoController.initialize(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done) {
                    videoController.play();
                    return Center(
                      child: AspectRatio(
                        aspectRatio: videoController.value.aspectRatio,
                        child: VideoPlayer(videoController),
                      ),
                    );
                  }
                  return _buildMediaLoadingIndicator();
                },
              ),
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    if (videoController.value.isPlaying) {
                      videoController.pause();
                    } else {
                      videoController.play();
                    }
                  },
                ),
              ),
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
                    videoController.dispose();
                    Navigator.pop(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, -1),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_selectedMedia != null)
            _buildSelectedMediaPreview(),
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
              Expanded(
                child: TextField(
                  controller: _messageController,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: _selectedMedia != null
                        ? 'Add a caption...'
                        : 'Type a message...',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(25),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                  ),
                  onChanged: (text) {
                    setState(() {
                      _isTyping = text.isNotEmpty || _selectedMedia != null;
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              if (_selectedMedia == null)
                IconButton(
                  icon: const Icon(Icons.camera_alt),
                  onPressed: _openCameraPicker,
                ),
              CircleAvatar(
                radius: 22,
                backgroundColor: Colors.red,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white),
                  onPressed: () {
                    if (_selectedMedia != null) {
                      _sendMediaMessage();
                    } else {
                      _sendMessage();
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedMediaPreview() {
    return GestureDetector(
      onTap: () {
        if (_selectedMedia != null) {
          if (_selectedMediaType == AssetType.video) {
            _showFullScreenVideo(_selectedMedia!.path);
          } else {
            _showFullScreenImage(_selectedMedia!.path);
          }
        }
      },
      child: Container(
        height: 100,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(11),
              child: _selectedMediaType == AssetType.video
                  ? Container(
                      color: Colors.black,
                      child: const Icon(
                        Icons.play_circle_fill,
                        color: Colors.white,
                        size: 40,
                      ),
                    )
                  : Image.file(
                      _selectedMedia!,
                      height: 100,
                      width: 100,
                      fit: BoxFit.cover,
                    ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedMedia = null;
                    _selectedMediaType = null;
                    _isTyping = _messageController.text.isNotEmpty;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.close,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
      if (await _audioRecorder.hasPermission()) {
        // Create necessary directories
        final Directory? externalDir = await getExternalStorageDirectory();
        if (externalDir == null) {
          throw Exception('Cannot access external storage');
        }

        final Directory mediaDir = Directory('${externalDir.path}/emergency_chats/${widget.emergencyUserId}');
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
        }

        final String timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
        final String filename = 'audio_$timestamp.m4a';
        final String filePath = '${mediaDir.path}/$filename';
        
        await _audioRecorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            sampleRate: 16000,
            numChannels: 1,
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
      }
    } catch (e) {
      log('Error starting recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to start recording: $e')),
      );
    }
  }

  Future<void> _stopVoiceRecording() async {
    final query = _messageController.text.trim();
    _messageController.clear();

    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        setState(() => _isProcessing = true);
        
        final mediaUrls = await _uploadMediaToStorage(File(path), 'audio');

        final messageData = {
          'text': "[Audio]${query.isNotEmpty ? ': $query' : ''}",
          'senderId': widget.currentUserId,
          'senderName': _currentUserName,
          'senderRole': _currentUserRole,
          'timestamp': Timestamp.now(),
          'type': 'message',
          'mediaType': 'audio',
          'mediaUrl': mediaUrls['downloadUrl'],
          'localPath': mediaUrls['localPath'],
        };

        setState(() {
          _messages.add(messageData);
          _isRecording = false;
          _isProcessing = false;
        });

        // Add to Firestore
        await _firestore
            .collection('emergency_group_chats')
            .doc(_chatRoomId)
            .collection('messages')
            .add(messageData);

        await _firestore
            .collection('emergency_group_chats')
            .doc(_chatRoomId)
            .update({
          'lastMessage': messageData['text'],
          'lastMessageTime': FieldValue.serverTimestamp(),
          'messageCount': FieldValue.increment(1),
        });
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      log('Error stopping recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save recording: $e')),
      );
    }
  }

  void _playAudioRecording(String audioUrl) async {
    // Case 1: Same audio is already playing - pause it
    if (_currentlyPlayingPath == audioUrl && _isPlaying) {
      await _audioPlayer.pause();
      setState(() {
        _isPlaying = false;
      });
      return;
    }

    // Case 2: Same audio is paused - resume it
    if (_currentlyPlayingPath == audioUrl && !_isPlaying) {
      await _audioPlayer.play();
      setState(() {
        _isPlaying = true;
      });
      return;
    }

    // Case 3: Different audio or no audio playing - start new audio
    try {
      await _audioPlayer.setUrl(audioUrl);
      await _audioPlayer.play();

      setState(() {
        _currentlyPlayingPath = audioUrl;
        _isPlaying = true;
      });

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
        SnackBar(content: Text('Failed to play audio: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Emergency: ${widget.emergencyUserName}'),
            Text(
              '${widget.emergencyType} • $_participantCount participant${_participantCount != 1 ? 's' : ''}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red,
        actions: [
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.info_outline),
                onPressed: () {
                  // Mark info as read when viewing participants
                  setState(() {
                    _unreadInfoCount = 0;
                  });
                  _showParticipantsInfo();
                },
              ),
              if (_unreadInfoCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      _unreadInfoCount > 9 ? '9+' : _unreadInfoCount.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Emergency status banner
                Container(
                  padding: const EdgeInsets.all(10),
                  color: Colors.red.shade50,
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 13,
                            ),
                            children: [
                              const TextSpan(
                                text: "EMERGENCY COORDINATION CHAT: ",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              TextSpan(
                                text:
                                    "All messages in this group are visible to ${widget.emergencyUserName} and all helpers",
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // New message count indicator
                if (_unreadMessagesCount > 0)
                  GestureDetector(
                    onTap: () {
                      _scrollToBottom();
                      _updateLastSeen();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 16),
                      color: Colors.green.shade100,
                      child: Row(
                        children: [
                          Icon(Icons.mark_chat_unread,
                              color: Colors.green.shade800),
                          const SizedBox(width: 8),
                          Text(
                            '$_unreadMessagesCount new message${_unreadMessagesCount != 1 ? 's' : ''}',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Tap to view',
                            style: TextStyle(
                              color: Colors.green.shade800,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
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
                                const Icon(Icons.chat_bubble_outline,
                                    size: 48, color: Colors.grey),
                                const SizedBox(height: 16),
                                Text(
                                  "No messages yet\nBe the first to send a message",
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.grey),
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
                              final isMe = messageData['senderId'] ==
                                  widget.currentUserId;
                              final messageText = messageData['text'] as String;
                              final senderName =
                                  messageData['senderName'] as String? ??
                                      'Unknown';
                              final senderRole =
                                  messageData['senderRole'] as String? ??
                                      'helper';
                              final messageType =
                                  messageData['type'] as String? ?? 'message';
                              final timestamp =
                                  messageData['timestamp'] as Timestamp?;

                              // Check if this message is unread
                              bool isUnread = false;
                              if (timestamp != null &&
                                  _lastSeenTimestamp != null &&
                                  !isMe) {
                                isUnread =
                                    timestamp.compareTo(_lastSeenTimestamp!) >
                                        0;
                              }

                              // For system messages
                              if (messageType == 'system') {
                                return Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Text(
                                        messageText,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                          fontStyle: FontStyle.italic,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // Regular messages
                              return _buildMessageBubble(messageData);
                            },
                          ),
                  ),
                ),

                // Message input
                _buildMessageInput(),
              ],
            ),
    );
  }

  void _showParticipantsInfo() async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const Center(child: CircularProgressIndicator());
        },
      );

      // Fetch the latest data from Firestore
      DocumentSnapshot chatRoom = await _firestore
          .collection('emergency_group_chats')
          .doc(_chatRoomId)
          .get();

      // Dismiss the loading dialog
      Navigator.pop(context);

      if (!chatRoom.exists) return;

      final data = chatRoom.data() as Map<String, dynamic>;
      final participantDetails =
          data['participantDetails'] as Map<String, dynamic>;
      print('participantDetails: $participantDetails');
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency Chat Participants',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: ListView.builder(
                    itemCount: participantDetails.length,
                    itemBuilder: (context, index) {
                      final userId = participantDetails.keys.elementAt(index);
                      final userInfo =
                          participantDetails[userId] as Map<String, dynamic>;
                      final name = userInfo['name'] as String? ?? 'Unknown';
                      final role = userInfo['role'] as String? ?? 'helper';
                      final joinedAt = userInfo['joinedAt'] as Timestamp?;
                      final lastSeen = userInfo['lastSeen'] as Timestamp?;

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: _getSenderColor(role),
                          child: role == 'emergency'
                              ? const Icon(
                                  Icons.warning,
                                  color: Colors.white,
                                  size: 18,
                                )
                              : Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: Colors.white),
                                ),
                        ),
                        title: Row(
                          children: [
                            Text(name),
                            if (userId == widget.currentUserId) ...[
                              const SizedBox(width: 8),
                              const Text(
                                '(You)',
                                style: TextStyle(
                                  fontStyle: FontStyle.italic,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              role == 'emergency' ? 'Emergency User' : 'Helper',
                              style: TextStyle(color: _getSenderColor(role)),
                            ),
                            Text(
                              'Joined: ${formatTimestamp(joinedAt)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            Text(
                              'Last seen: ${formatTimestamp(lastSeen)}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    } catch (e) {
      log('Error showing participants: $e');
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messageSubscription?.cancel();
    _chatRoomSubscription?.cancel();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }
}
