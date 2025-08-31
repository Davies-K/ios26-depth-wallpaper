import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// A Flutter package that creates iOS-style depth wallpapers
/// by separating foreground subjects from background using AI
class DepthWallpaper extends StatefulWidget {
  final String imagePath;
  final Widget clockWidget;
  final String? removeBackgroundApiKey; // For remove.bg or similar service
  final bool useLocalProcessing; // Fallback to basic edge detection
  final Duration animationDuration;
  final Curve animationCurve;

  const DepthWallpaper({
    super.key,
    required this.imagePath,
    required this.clockWidget,
    this.removeBackgroundApiKey,
    this.useLocalProcessing = true,
    this.animationDuration = const Duration(milliseconds: 500),
    this.animationCurve = Curves.easeInOut,
  });

  @override
  State<DepthWallpaper> createState() => _DepthWallpaperState();
}

class _DepthWallpaperState extends State<DepthWallpaper>
    with TickerProviderStateMixin {
  ui.Image? _foregroundImage;
  ui.Image? _backgroundImage;
  bool _isProcessing = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: widget.animationCurve,
      ),
    );
    _processImage();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _processImage() async {
    try {
      // Load the original image
      final ByteData data = await rootBundle.load(widget.imagePath);
      final Uint8List bytes = data.buffer.asUint8List();

      // Process the image to separate foreground and background
      if (widget.removeBackgroundApiKey != null) {
        await _processWithAI(bytes);
      } else if (widget.useLocalProcessing) {
        await _processLocally(bytes);
      }

      setState(() {
        _isProcessing = false;
      });

      _animationController.forward();
    } catch (e) {
      print('Error processing image: $e');
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _processWithAI(Uint8List imageBytes) async {
    try {
      // Using remove.bg API as an example
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('https://api.remove.bg/v1.0/removebg'),
      );

      request.headers['X-Api-Key'] = widget.removeBackgroundApiKey!;
      request.files.add(
        http.MultipartFile.fromBytes(
          'image_file',
          imageBytes,
          filename: 'image.jpg',
        ),
      );
      request.fields['size'] = 'auto';

      final response = await request.send();

      if (response.statusCode == 200) {
        final foregroundBytes = await response.stream.toBytes();

        // Create foreground image
        final ui.Codec foregroundCodec = await ui.instantiateImageCodec(
          foregroundBytes,
        );
        final ui.FrameInfo foregroundFrame = await foregroundCodec
            .getNextFrame();
        _foregroundImage = foregroundFrame.image;

        // Create background by blurring original
        _backgroundImage = await _createBlurredBackground(imageBytes);
      }
    } catch (e) {
      print('AI processing failed, falling back to local processing: $e');
      await _processLocally(imageBytes);
    }
  }

  Future<void> _processLocally(Uint8List imageBytes) async {
    try {
      // Basic local processing using edge detection and masking
      final img.Image? originalImg = img.decodeImage(imageBytes);
      if (originalImg == null) return;

      // Create a simple subject detection (this is a simplified approach)
      // In a real implementation, you'd use more sophisticated algorithms
      final img.Image foregroundImg = _extractSubject(originalImg);
      final img.Image backgroundImg = _createBackground(originalImg);

      // Convert to UI images
      _foregroundImage = await _imgToUiImage(foregroundImg);
      _backgroundImage = await _imgToUiImage(backgroundImg);
    } catch (e) {
      print('Local processing failed: $e');
    }
  }

  img.Image _extractSubject(img.Image original) {
    // Simplified subject extraction using center-focused approach
    // This is a basic implementation - real AI would be much more accurate
    final img.Image result = img.Image.from(original);
    final centerX = original.width ~/ 2;
    final centerY = original.height ~/ 2;
    final radius = (original.width * 0.3).round();

    for (int y = 0; y < original.height; y++) {
      for (int x = 0; x < original.width; x++) {
        final distance =
            ((x - centerX) * (x - centerX) + (y - centerY) * (y - centerY));
        if (distance > radius * radius) {
          // Make pixels outside center radius transparent
          result.setPixel(x, y, img.ColorRgba8(0, 0, 0, 0));
        }
      }
    }
    return result;
  }

  img.Image _createBackground(img.Image original) {
    // Create a blurred version for background
    return img.gaussianBlur(original, radius: 10);
  }

  Future<ui.Image> _createBlurredBackground(Uint8List imageBytes) async {
    final img.Image? originalImg = img.decodeImage(imageBytes);
    if (originalImg == null) throw Exception('Failed to decode image');

    final img.Image blurred = img.gaussianBlur(originalImg, radius: 15);
    return await _imgToUiImage(blurred);
  }

  Future<ui.Image> _imgToUiImage(img.Image image) async {
    final ui.Codec codec = await ui.instantiateImageCodec(
      Uint8List.fromList(img.encodePng(image)),
    );
    final ui.FrameInfo frameInfo = await codec.getNextFrame();
    return frameInfo.image;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: _isProcessing
          ? const Center(child: CircularProgressIndicator())
          : AnimatedBuilder(
              animation: _fadeAnimation,
              builder: (context, child) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background layer (blurred)
                    if (_backgroundImage != null)
                      Positioned.fill(
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: CustomPaint(
                            painter: ImagePainter(_backgroundImage!),
                          ),
                        ),
                      ),

                    // Clock/Text layer (middle)
                    Positioned.fill(
                      child: Opacity(
                        opacity: _fadeAnimation.value,
                        child: widget.clockWidget,
                      ),
                    ),

                    // Foreground subject layer (top)
                    if (_foregroundImage != null)
                      Positioned.fill(
                        child: Opacity(
                          opacity: _fadeAnimation.value,
                          child: CustomPaint(
                            painter: ImagePainter(_foregroundImage!),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}

class ImagePainter extends CustomPainter {
  final ui.Image image;

  ImagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..filterQuality = FilterQuality.high;

    final double scaleX = size.width / image.width;
    final double scaleY = size.height / image.height;
    final double scale = scaleX > scaleY ? scaleX : scaleY;

    final double scaledWidth = image.width * scale;
    final double scaledHeight = image.height * scale;

    final Offset offset = Offset(
      (size.width - scaledWidth) / 2,
      (size.height - scaledHeight) / 2,
    );

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(offset.dx, offset.dy, scaledWidth, scaledHeight),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// iOS-style lock screen clock widget
class IOSLockScreenClock extends StatefulWidget {
  final Color textColor;
  final Color shadowColor;
  final double timeSize;
  final double dateSize;
  final FontWeight timeWeight;
  final FontWeight dateWeight;
  final bool show24Hour;
  final EdgeInsets padding;

  const IOSLockScreenClock({
    super.key,
    this.textColor = Colors.white,
    this.shadowColor = const Color(0x4D000000),
    this.timeSize = 120.0,
    this.dateSize = 20.0,
    this.timeWeight = FontWeight.w200,
    this.dateWeight = FontWeight.w500,
    this.show24Hour = false,
    this.padding = const EdgeInsets.all(16.0),
  });

  @override
  State<IOSLockScreenClock> createState() => _IOSLockScreenClockState();
}

class _IOSLockScreenClockState extends State<IOSLockScreenClock> {
  late DateTime _currentTime;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatTime(DateTime time) {
    if (widget.show24Hour) {
      return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      int hour = time.hour;
      if (hour == 0) hour = 12;
      if (hour > 12) hour -= 12;
      return '${hour.toString()}:${time.minute.toString().padLeft(2, '0')}';
    }
  }

  String _formatDate(DateTime time) {
    const List<String> weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const List<String> months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    String weekday = weekdays[time.weekday - 1];
    String month = months[time.month - 1];

    return '$weekday, $month ${time.day}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: widget.padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Time display
          Transform(
            transform: Matrix4.identity()..scale(.8, 2.5),
            alignment: Alignment.center,
            child: 
          Text(
            _formatTime(_currentTime),
            style: TextStyle(
              fontSize: widget.timeSize,
              fontWeight: widget.timeWeight,
              color: widget.textColor,
              height: 0.9,
              letterSpacing: -2.0,
              shadows: [
                Shadow(
                  offset: const Offset(0, 3),
                  blurRadius: 12,
                  color: widget.shadowColor,
                ),
                Shadow(
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                  color: widget.shadowColor.withOpacity(0.5),
                ),
              ],
            ),
          ),
          ),

          const SizedBox(height: 120),

          // Date display
          Text(
            _formatDate(_currentTime),
            style: TextStyle(
              fontSize: widget.dateSize,
              fontWeight: widget.dateWeight,
              color: widget.textColor.withOpacity(0.9),
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  offset: const Offset(0, 2),
                  blurRadius: 8,
                  color: widget.shadowColor,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact iOS-style clock for smaller spaces
class CompactIOSClock extends StatefulWidget {
  final Color textColor;
  final double fontSize;
  final bool showSeconds;
  final bool show24Hour;

  const CompactIOSClock({
    super.key,
    this.textColor = Colors.white,
    this.fontSize = 16.0,
    this.showSeconds = false,
    this.show24Hour = true,
  });

  @override
  State<CompactIOSClock> createState() => _CompactIOSClockState();
}

class _CompactIOSClockState extends State<CompactIOSClock> {
  late DateTime _currentTime;
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _currentTime = DateTime.now();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _currentTime = DateTime.now();
      });
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  String _formatCompactTime(DateTime time) {
    String timeStr;
    if (widget.show24Hour) {
      timeStr =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
    } else {
      int hour = time.hour;
      String period = hour >= 12 ? 'PM' : 'AM';
      if (hour == 0) hour = 12;
      if (hour > 12) hour -= 12;
      timeStr =
          '${hour.toString()}:${time.minute.toString().padLeft(2, '0')} $period';
    }

    if (widget.showSeconds) {
      timeStr += ':${time.second.toString().padLeft(2, '0')}';
    }

    return timeStr;
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _formatCompactTime(_currentTime),
      style: TextStyle(
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w600,
        color: widget.textColor,
        shadows: [
          Shadow(
            offset: const Offset(0, 1),
            blurRadius: 3,
            color: Colors.black.withOpacity(0.3),
          ),
        ],
      ),
    );
  }
}

/// Custom iOS-style status bar clock
class IOSStatusBarClock extends StatelessWidget {
  final DateTime time;
  final Color textColor;
  final double fontSize;

  const IOSStatusBarClock({
    super.key,
    required this.time,
    this.textColor = Colors.white,
    this.fontSize = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w600,
        color: textColor,
        letterSpacing: 0.5,
      ),
    );
  }
}
// Complete iOS lock screen replica
class IOSLockScreenReplica extends StatelessWidget {
  final String imagePath;
  final String? apiKey;

  const IOSLockScreenReplica({super.key, required this.imagePath, this.apiKey});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Depth wallpaper with clock
          DepthWallpaper(
            imagePath: imagePath,
            removeBackgroundApiKey: apiKey,
            clockWidget: const Center(child: IOSLockScreenClock()),
          ),

          // Status bar
          Positioned(
            top: MediaQuery.of(context).padding.top,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Carrier and signal
                  Row(
                    children: [
                      Text(
                        'Verizon',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              offset: const Offset(0, 1),
                              blurRadius: 3,
                              color: Colors.black.withOpacity(0.3),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Signal bars
                      Row(
                        children: List.generate(4, (index) {
                          return Container(
                            margin: const EdgeInsets.only(right: 2),
                            width: 4,
                            height: 4 + (index * 2).toDouble(),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          );
                        }),
                      ),
                    ],
                  ),

                  // Time
                  IOSStatusBarClock(
                    time: DateTime.now(),
                    textColor: Colors.white,
                  ),

                  // Battery and icons
                  Row(
                    children: [
                      Icon(Icons.wifi, color: Colors.white, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        '100%',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 22,
                        height: 12,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.white, width: 1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Container(
                          margin: const EdgeInsets.all(1),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(1),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Bottom unlock indicator
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 150,
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(3),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Advanced version with parallax effect
class AdvancedDepthWallpaper extends StatefulWidget {
  final String imagePath;
  final Widget clockWidget;
  final String? removeBackgroundApiKey;
  final bool enableParallax;
  final double parallaxIntensity;

  const AdvancedDepthWallpaper({
    super.key,
    required this.imagePath,
    required this.clockWidget,
    this.removeBackgroundApiKey,
    this.enableParallax = true,
    this.parallaxIntensity = 0.5,
  });

  @override
  State<AdvancedDepthWallpaper> createState() => _AdvancedDepthWallpaperState();
}

class _AdvancedDepthWallpaperState extends State<AdvancedDepthWallpaper> {
  Offset _gyroscopeOffset = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: widget.enableParallax ? _handlePanUpdate : null,
      child: Stack(
        children: [
          // Background with parallax
          Transform.translate(
            offset: _gyroscopeOffset * -widget.parallaxIntensity,
            child: DepthWallpaper(
              imagePath: widget.imagePath,
              removeBackgroundApiKey: widget.removeBackgroundApiKey,
              clockWidget: Container(), // Empty for background layer
            ),
          ),

          // Clock with subtle parallax
          Transform.translate(
            offset: _gyroscopeOffset * widget.parallaxIntensity * 0.3,
            child: widget.clockWidget,
          ),
        ],
      ),
    );
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    setState(() {
      _gyroscopeOffset = Offset(
        (_gyroscopeOffset.dx + details.delta.dx * 0.1).clamp(-20.0, 20.0),
        (_gyroscopeOffset.dy + details.delta.dy * 0.1).clamp(-20.0, 20.0),
      );
    });
  }
}
