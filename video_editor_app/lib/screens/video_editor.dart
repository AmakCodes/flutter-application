import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:gallery_saver/gallery_saver.dart';
import 'package:ffmpeg_kit_flutter_min_gpl/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

class VideoEditorScreen extends StatefulWidget {
  const VideoEditorScreen({super.key});

  @override
  // ignore: library_private_types_in_public_api
  _VideoEditorScreenState createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _controller;
  XFile? _videoFile;
  XFile? _overlayImage;
  XFile? _secondVideoFile;
  XFile? _newAudioFile;
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _pickVideo() async {
    await _requestPermissions();
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      _videoFile = pickedFile;
      _initializeVideo();
    }
  }

  Future<void> _pickSecondVideo() async {
    await _requestPermissions();
    final picker = ImagePicker();
    final pickedFile = await picker.pickVideo(source: ImageSource.gallery);
    if (pickedFile != null) {
      _secondVideoFile = pickedFile;
      _showMessage("Second video selected.");
    }
  }

  Future<void> _pickNewAudio() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _newAudioFile = XFile(result.files.single.path!);
      });
      _showMessage("New audio selected.");
    } else {
      _showMessage("Audio selection cancelled.");
    }
  }

  Future<void> _pickOverlayImage() async {
    await _requestPermissions();
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _overlayImage = picked);
      _showMessage("Image selected for overlay.");
    }
  }

  void _initializeVideo() {
    _controller?.dispose();
    _controller = VideoPlayerController.file(File(_videoFile!.path))
      ..initialize().then((_) {
        setState(() {});
        _controller!.play();
      });
  }

  Future<String> _getOutputPath(String suffix) async {
    final dir = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return "${dir.path}/video_$timestamp$suffix.mp4";
  }

  Future<void> _trimVideo() async {
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -ss 00:00:02 -t 00:00:05 -c copy "{output}"',
      "Video trimmed and saved.",
    );
  }

  Future<void> _changeSpeed(double speedFactor) async {
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -filter_complex "[0:v]setpts=${1 / speedFactor}*PTS[v];[0:a]atempo=$speedFactor[a]" -map "[v]" -map "[a]" "{output}"',
      "Speed changed and saved.",
    );
  }

  Future<void> _addTextOverlay() async {
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -vf "drawtext=text=\'Sample Text\':fontcolor=white:fontsize=30:x=10:y=H-th-10" -codec:a copy "{output}"',
      "Text overlay added and saved.",
    );
  }

  Future<void> _addImageOverlay() async {
    if (_overlayImage == null) {
      _showMessage("Please select an image first.");
      return;
    }
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -i "${_overlayImage!.path}" -filter_complex "overlay=10:10" "{output}"',
      "Image overlay added and saved.",
    );
  }

  Future<void> _cropVideo() async {
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -filter:v "crop=300:300:100:100" "{output}"',
      "Video cropped and saved.",
    );
  }

  Future<void> _replaceAudio() async {
    if (_newAudioFile == null) {
      _showMessage("Please select an audio file first.");
      return;
    }
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -i "${_newAudioFile!.path}" -map 0:v -map 1:a -c:v copy -shortest "{output}"',
      "Audio replaced and saved.",
    );
  }

  Future<void> _exportLowRes() async {
    await _runFFmpegCommand(
      '-i "${_videoFile!.path}" -vf "scale=640:360" "{output}"',
      "Exported at 360p resolution.",
    );
  }

  Future<void> _mergeVideos() async {
    if (_secondVideoFile == null) {
      _showMessage("Please select the second video.");
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final inputListPath = '${tempDir.path}/input.txt';
    final inputFile = File(inputListPath);
    await inputFile.writeAsString(
      "file '${_videoFile!.path}'\nfile '${_secondVideoFile!.path}'\n",
    );

    await _runFFmpegCommand(
      '-f concat -safe 0 -i "$inputListPath" -c copy "{output}"',
      "Videos merged and saved.",
    );
  }

  Future<void> _runFFmpegCommand(
    String commandTemplate,
    String successMessage,
  ) async {
    if (_videoFile == null) return;
    setState(() => _isProcessing = true);

    final outputPath = await _getOutputPath("_edit");
    final command = commandTemplate.replaceAll("{output}", outputPath);

    await FFmpegKit.execute(command).then((_) async {
      await GallerySaver.saveVideo(outputPath);
      _showMessage(successMessage);
    });

    setState(() => _isProcessing = false);
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      if (!await Permission.storage.isGranted) {
        await Permission.storage.request();
      }
      if (!await Permission.videos.isGranted) {
        await Permission.videos.request();
      }
      if (!await Permission.audio.isGranted) {
        await Permission.audio.request();
      }
    }
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Video Editor"),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.video_library),
              label: const Text("Pick Video"),
            ),
            const SizedBox(height: 10),
            if (_controller != null && _controller!.value.isInitialized)
              AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: VideoPlayer(_controller!),
              ),
            const SizedBox(height: 10),
            if (_videoFile != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _trimVideo,
                    icon: const Icon(Icons.cut),
                    label: const Text("Trim Video"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _changeSpeed(0.5),
                    icon: const Icon(Icons.slow_motion_video),
                    label: const Text("Slow Motion (0.5x)"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : () => _changeSpeed(2.0),
                    icon: const Icon(Icons.fast_forward),
                    label: const Text("Fast Motion (2x)"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _addTextOverlay,
                    icon: const Icon(Icons.text_fields),
                    label: const Text("Add Text Overlay"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickOverlayImage,
                    icon: const Icon(Icons.image),
                    label: const Text("Select Image for Overlay"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _addImageOverlay,
                    icon: const Icon(Icons.photo),
                    label: const Text("Add Image Overlay"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _cropVideo,
                    icon: const Icon(Icons.crop),
                    label: const Text("Crop Video"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickNewAudio,
                    icon: const Icon(Icons.audiotrack),
                    label: const Text("Select New Audio"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _replaceAudio,
                    icon: const Icon(Icons.music_note),
                    label: const Text("Replace Audio"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _exportLowRes,
                    icon: const Icon(Icons.sd),
                    label: const Text("Export 360p"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _pickSecondVideo,
                    icon: const Icon(Icons.video_call),
                    label: const Text("Select Second Video"),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _mergeVideos,
                    icon: const Icon(Icons.merge_type),
                    label: const Text("Merge Videos"),
                  ),
                ],
              ),
            if (_isProcessing)
              const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
    );
  }
}
