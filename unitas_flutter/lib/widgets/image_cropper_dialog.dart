import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

/// Menampilkan dialog crop & zoom gambar dengan pilihan rasio yang bekerja di Web, Android, iOS, dan Desktop.
Future<Uint8List?> showImageCropDialog(
  BuildContext context,
  Uint8List imageBytes, {
  double aspectRatio = 1.0,
  bool isCircle = false,
  String title = 'Sesuaikan & Crop Foto',
}) {
  return showDialog<Uint8List>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImageCropDialog(
      imageBytes: imageBytes,
      initialAspectRatio: aspectRatio,
      isCircle: isCircle,
      title: title,
    ),
  );
}

class _ImageCropDialog extends StatefulWidget {
  final Uint8List imageBytes;
  final double initialAspectRatio;
  final bool isCircle;
  final String title;

  const _ImageCropDialog({
    required this.imageBytes,
    required this.initialAspectRatio,
    required this.isCircle,
    required this.title,
  });

  @override
  State<_ImageCropDialog> createState() => _ImageCropDialogState();
}

class _ImageCropDialogState extends State<_ImageCropDialog> {
  final _cropKey = GlobalKey();
  final _transformCtrl = TransformationController();
  late final MemoryImage _memoryImage;
  late double _aspectRatio;
  final ValueNotifier<double> _zoomNotifier = ValueNotifier<double>(1.0);
  bool _saving = false;

  static const List<Map<String, dynamic>> _ratios = [
    {'label': '1:1', 'value': 1.0},
    {'label': '4:3', 'value': 4 / 3},
    {'label': '16:9', 'value': 16 / 9},
    {'label': '3:4', 'value': 3 / 4},
  ];

  @override
  void initState() {
    super.initState();
    _aspectRatio = widget.initialAspectRatio;
    _memoryImage = MemoryImage(widget.imageBytes);
  }

  @override
  void dispose() {
    _transformCtrl.dispose();
    _zoomNotifier.dispose();
    super.dispose();
  }

  void _setZoom(double value) {
    _zoomNotifier.value = value;
    final matrix = Matrix4.identity()..scaleByDouble(value, value, 1.0, 1.0);
    _transformCtrl.value = matrix;
  }

  void _resetTransform() {
    _zoomNotifier.value = 1.0;
    _transformCtrl.value = Matrix4.identity();
  }

  Future<void> _confirmCrop() async {
    setState(() => _saving = true);
    try {
      final boundary = _cropKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        if (mounted) Navigator.pop(context, widget.imageBytes);
        return;
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (mounted) {
        Navigator.pop(context, byteData?.buffer.asUint8List() ?? widget.imageBytes);
      }
    } catch (_) {
      if (mounted) Navigator.pop(context, widget.imageBytes);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: brandBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(widget.title, style: subTitle.copyWith(fontSize: 16)),
                  IconButton(
                    icon: const Icon(Icons.close, color: brandNavy, size: 20),
                    onPressed: _saving ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Pilih ukuran crop, lalu geser & perbesar gambar',
                style: caption,
              ),
              if (!widget.isCircle) ...[
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: _ratios.map((r) {
                    final ratioVal = (r['value'] as num).toDouble();
                    final selected = (_aspectRatio - ratioVal).abs() < 0.02;
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: InkWell(
                        onTap: () {
                          setState(() => _aspectRatio = ratioVal);
                          _resetTransform();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? brandNavy : surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: selected ? brandNavy : borderColor),
                          ),
                          child: Text(
                            r['label'] as String,
                            style: caption.copyWith(
                              color: selected ? Colors.white : dim1,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: _aspectRatio,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          key: _cropKey,
                          child: Container(
                            color: Colors.black,
                            child: InteractiveViewer(
                              transformationController: _transformCtrl,
                              minScale: 1.0,
                              maxScale: 4.0,
                              boundaryMargin: const EdgeInsets.all(140),
                              onInteractionEnd: (_) {
                                final scale = _transformCtrl.value.getMaxScaleOnAxis();
                                _zoomNotifier.value = scale.clamp(1.0, 4.0);
                              },
                              child: Image(
                                image: _memoryImage,
                                fit: BoxFit.cover,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        ),
                        IgnorePointer(
                          child: CustomPaint(
                            painter: _CropMaskPainter(isCircle: widget.isCircle),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.zoom_out, size: 18, color: dim1),
                  Expanded(
                    child: ValueListenableBuilder<double>(
                      valueListenable: _zoomNotifier,
                      builder: (_, zoom, _) => Slider(
                        value: zoom.clamp(1.0, 4.0),
                        min: 1.0,
                        max: 4.0,
                        activeColor: brandNavy,
                        inactiveColor: dim3,
                        onChanged: _setZoom,
                      ),
                    ),
                  ),
                  Icon(Icons.zoom_in, size: 18, color: dim1),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _resetTransform,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('Reset', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: brandNavy,
                        side: BorderSide(color: borderColor),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: Text('Batal', style: caption.copyWith(color: brandNavy, fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: brandNavy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      onPressed: _saving ? null : _confirmCrop,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                          : Text('Gunakan Foto', style: buttonStyle),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CropMaskPainter extends CustomPainter {
  final bool isCircle;
  const _CropMaskPainter({required this.isCircle});

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    if (isCircle) {
      final radius = (size.shortestSide / 2) - 4;
      final center = Offset(size.width / 2, size.height / 2);
      final overlayPath = Path()
        ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
        ..addOval(Rect.fromCircle(center: center, radius: radius))
        ..fillType = PathFillType.evenOdd;
      canvas.drawPath(overlayPath, Paint()..color = Colors.black.withValues(alpha: 0.45));
      canvas.drawCircle(center, radius, borderPaint);
    } else {
      // Rule-of-thirds grid + border
      final gridPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..strokeWidth = 0.8;
      canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), gridPaint);
      canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), gridPaint);
      canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), gridPaint);
      canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), gridPaint);
      canvas.drawRect(Rect.fromLTWH(1, 1, size.width - 2, size.height - 2), borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropMaskPainter oldDelegate) => oldDelegate.isCircle != isCircle;
}
