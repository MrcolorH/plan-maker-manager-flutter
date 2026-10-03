/// 原图等比框选与裁剪页面
/// 强制锁定各模块原生宽高比，保证截取画面精确吻合目标槽位
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageCropPage extends StatefulWidget {
  final File originalImageFile;
  final double targetAspectRatio; // 目标模块宽高比 (width / height)
  final String moduleTitle; // 模块名称，例如“全屏壁纸”、“打气看板娘”
  final String moduleKey; // 模块标识，例如 'bg', 'mascot', 'card'
  final bool isCircle; // 是否是圆形辅助框（如头像挂件）
  final ui.Image? overrideImage; // 用于单元测试或即时预览注入

  const ImageCropPage({
    super.key,
    required this.originalImageFile,
    required this.targetAspectRatio,
    required this.moduleTitle,
    required this.moduleKey,
    this.isCircle = false,
    this.overrideImage,
  });

  @override
  State<ImageCropPage> createState() => _ImageCropPageState();
}

class _ImageCropPageState extends State<ImageCropPage> {
  ui.Image? _decodedImage;
  bool _loading = true;
  bool _cropping = false;

  // 手势与变换参数
  double _scale = 1.0;
  double _baseScale = 1.0;
  Offset _offset = Offset.zero;

  // 基础视口与取景框数据
  Size _viewportSize = Size.zero;
  Rect _cropBoxRect = Rect.zero;
  Size _fittedImageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    if (widget.overrideImage != null) {
      _decodedImage = widget.overrideImage;
      _loading = false;
    } else {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    try {
      final bytes = await widget.originalImageFile.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (mounted) {
        setState(() {
          _decodedImage = frame.image;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载原图失败: $e')),
        );
      }
    }
  }

  void _calculateLayout(Size size) {
    if (_decodedImage == null || size.isEmpty) return;
    if (_viewportSize == size) return;
    _viewportSize = size;

    // 1. 在可用视口内计算居中的取景框（留出适当边距）
    const padding = 24.0;
    final maxW = size.width - padding * 2;
    final maxH = size.height - padding * 2;

    double boxW;
    double boxH;
    final targetRatio = widget.targetAspectRatio;

    if (maxW / maxH > targetRatio) {
      // 受高度限制
      boxH = maxH;
      boxW = boxH * targetRatio;
    } else {
      // 受宽度限制
      boxW = maxW;
      boxH = boxW / targetRatio;
    }

    final boxLeft = (size.width - boxW) / 2;
    final boxTop = (size.height - boxH) / 2;
    _cropBoxRect = Rect.fromLTWH(boxLeft, boxTop, boxW, boxH);

    // 2. 计算原图适配填满取景框的初始尺寸
    final imgW = _decodedImage!.width.toDouble();
    final imgH = _decodedImage!.height.toDouble();
    final imgRatio = imgW / imgH;

    double initW;
    double initH;
    if (imgRatio > targetRatio) {
      // 原图比框更宽，高度填满取景框
      initH = boxH;
      initW = initH * imgRatio;
    } else {
      // 原图比框更高，宽度填满取景框
      initW = boxW;
      initH = initW / imgRatio;
    }

    _fittedImageSize = Size(initW, initH);
    _scale = 1.0;
    // 初始居中在取景框
    _offset = Offset(
      boxLeft + (boxW - initW) / 2,
      boxTop + (boxH - initH) / 2,
    );
  }

  void _clampOffsetAndScale() {
    if (_cropBoxRect.isEmpty || _fittedImageSize.isEmpty) return;
    // 限制最小缩放倍数，使得原图在任何时候都至少完整覆盖取景框（不允许露黑边）
    _scale = math.max(_scale, 1.0);

    final currentW = _fittedImageSize.width * _scale;
    final currentH = _fittedImageSize.height * _scale;

    // 原图左边缘不能大于取景框左边缘，右边缘不能小于取景框右边缘
    final minX = math.min(_cropBoxRect.right - currentW, _cropBoxRect.left);
    final maxX = math.max(_cropBoxRect.right - currentW, _cropBoxRect.left);
    final clampedX = (minX >= maxX) ? minX : _offset.dx.clamp(minX, maxX);

    // 同理限制 Y 轴
    final minY = math.min(_cropBoxRect.bottom - currentH, _cropBoxRect.top);
    final maxY = math.max(_cropBoxRect.bottom - currentH, _cropBoxRect.top);
    final clampedY = (minY >= maxY) ? minY : _offset.dy.clamp(minY, maxY);

    _offset = Offset(clampedX, clampedY);
  }

  void _zoomBy(double factor) {
    if (_cropBoxRect.isEmpty || _fittedImageSize.isEmpty) return;
    setState(() {
      final targetScale = (_scale * factor).clamp(1.0, 8.0);
      if (_scale > 0) {
        final focal = _cropBoxRect.center;
        final scaleRatio = targetScale / _scale;
        _offset = focal - (focal - _offset) * scaleRatio;
      }
      _scale = targetScale;
      _clampOffsetAndScale();
    });
  }

  void _reset() {
    setState(() {
      _scale = 1.0;
      if (!_cropBoxRect.isEmpty && !_fittedImageSize.isEmpty) {
        _offset = Offset(
          _cropBoxRect.left + (_cropBoxRect.width - _fittedImageSize.width) / 2,
          _cropBoxRect.top + (_cropBoxRect.height - _fittedImageSize.height) / 2,
        );
      }
    });
  }

  Future<void> _doCrop() async {
    if (_decodedImage == null || _cropBoxRect.isEmpty) return;
    setState(() => _cropping = true);

    try {
      final img = _decodedImage!;
      final currentW = _fittedImageSize.width * _scale;
      final currentH = _fittedImageSize.height * _scale;

      // 1. 计算取景框相对于当前显示原图的归一化选区 (0.0 ~ 1.0)
      final normLeft = (_cropBoxRect.left - _offset.dx) / currentW;
      final normTop = (_cropBoxRect.top - _offset.dy) / currentH;
      final normWidth = _cropBoxRect.width / currentW;
      final normHeight = _cropBoxRect.height / currentH;

      // 2. 映射到真实原图像素尺寸
      final realX = (normLeft * img.width).clamp(0.0, img.width.toDouble());
      final realY = (normTop * img.height).clamp(0.0, img.height.toDouble());
      final realW = (normWidth * img.width).clamp(1.0, img.width - realX);
      final realH = (normHeight * img.height).clamp(1.0, img.height - realY);

      final srcRect = Rect.fromLTWH(realX, realY, realW, realH);
      final dstRect = Rect.fromLTWH(0, 0, realW, realH);

      // 3. 高精度离屏真实画布绘制裁剪
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder, dstRect);
      final paint = Paint()..filterQuality = FilterQuality.high;
      canvas.drawImageRect(img, srcRect, dstRect, paint);

      final picture = recorder.endRecording();
      final croppedImage = await picture.toImage(realW.toInt(), realH.toInt());
      final byteData = await croppedImage.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      // 4. 持久化存储到应用 Documents 目录
      final docDir = await getApplicationDocumentsDirectory();
      final outFile = File(
          '${docDir.path}/cropped_${widget.moduleKey}_${DateTime.now().millisecondsSinceEpoch}.png');
      await outFile.writeAsBytes(pngBytes);

      if (!mounted) return;
      Navigator.of(context).pop(outFile.path);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('截取失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cropping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white, size: 22),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          '原图框选 · ${widget.moduleTitle}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
            child: ElevatedButton(
              onPressed: (_loading || _cropping) ? null : _doCrop,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF5BA47C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: _cropping
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('完成框选', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white70))
          : LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                _calculateLayout(size);

                return Stack(
                  children: [
                    // 1. 底层原图可拖拽缩放层
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onScaleStart: (details) {
                          _baseScale = _scale;
                        },
                        onScaleUpdate: (details) {
                          setState(() {
                            // 1. 单指拖动或双指平移：逐帧累加物理位移增量
                            _offset += details.focalPointDelta;

                            // 2. 双指缩放：以触点中心缩放
                            if (details.scale != 1.0) {
                              final targetScale = (_baseScale * details.scale).clamp(1.0, 8.0);
                              if (_scale > 0) {
                                final scaleRatio = targetScale / _scale;
                                final focal = details.localFocalPoint;
                                _offset = focal - (focal - _offset) * scaleRatio;
                              }
                              _scale = targetScale;
                            }

                            _clampOffsetAndScale();
                          });
                        },
                        child: CustomPaint(
                          painter: _ImageCanvasPainter(
                            image: _decodedImage,
                            offset: _offset,
                            scale: _scale,
                            fittedSize: _fittedImageSize,
                          ),
                        ),
                      ),
                    ),

                    // 2. 顶层遮罩与等比取景框绘制
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _CropOverlayPainter(
                            cropBoxRect: _cropBoxRect,
                            isCircle: widget.isCircle,
                          ),
                        ),
                      ),
                    ),

                    // 3. 底部操作指引与辅助按钮
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 20,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const Text(
                              '单指拖动平移画面 · 双指捏合缩放取景',
                              style: TextStyle(color: Colors.white70, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              IconButton(
                                onPressed: () => _zoomBy(0.8),
                                icon: const Icon(Icons.zoom_out, color: Colors.white70, size: 20),
                                tooltip: '缩小',
                              ),
                              const SizedBox(width: 4),
                              TextButton.icon(
                                onPressed: _reset,
                                icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                                label: Text(
                                  '重置 (${_scale.toStringAsFixed(1)}x)',
                                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                onPressed: () => _zoomBy(1.25),
                                icon: const Icon(Icons.zoom_in, color: Colors.white70, size: 20),
                                tooltip: '放大',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// 原图绘制器
class _ImageCanvasPainter extends CustomPainter {
  final ui.Image? image;
  final Offset offset;
  final double scale;
  final Size fittedSize;

  _ImageCanvasPainter({
    required this.image,
    required this.offset,
    required this.scale,
    required this.fittedSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null || fittedSize.isEmpty) return;

    final srcRect = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
    final dstRect = Rect.fromLTWH(
      offset.dx,
      offset.dy,
      fittedSize.width * scale,
      fittedSize.height * scale,
    );

    final paint = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(image!, srcRect, dstRect, paint);
  }

  @override
  bool shouldRepaint(covariant _ImageCanvasPainter oldDelegate) {
    return oldDelegate.offset != offset ||
        oldDelegate.scale != scale ||
        oldDelegate.image != image;
  }
}

/// 裁剪蒙版与等比取景框绘制器
class _CropOverlayPainter extends CustomPainter {
  final Rect cropBoxRect;
  final bool isCircle;

  _CropOverlayPainter({required this.cropBoxRect, required this.isCircle});

  @override
  void paint(Canvas canvas, Size size) {
    if (cropBoxRect.isEmpty) return;

    // 1. 绘制半透明黑色遮罩（挖空取景框区域）
    final bgPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final holePath = Path()..addRect(cropBoxRect);
    final maskPath = Path.combine(PathOperation.difference, bgPath, holePath);

    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.68);
    canvas.drawPath(maskPath, maskPaint);

    // 2. 绘制取景框白色边框
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRect(cropBoxRect, borderPaint);

    // 3. 绘制九宫格三分辅助参考线
    final gridPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    final wThird = cropBoxRect.width / 3;
    final hThird = cropBoxRect.height / 3;

    // 竖线
    canvas.drawLine(
      Offset(cropBoxRect.left + wThird, cropBoxRect.top),
      Offset(cropBoxRect.left + wThird, cropBoxRect.bottom),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropBoxRect.left + wThird * 2, cropBoxRect.top),
      Offset(cropBoxRect.left + wThird * 2, cropBoxRect.bottom),
      gridPaint,
    );

    // 横线
    canvas.drawLine(
      Offset(cropBoxRect.left, cropBoxRect.top + hThird),
      Offset(cropBoxRect.right, cropBoxRect.top + hThird),
      gridPaint,
    );
    canvas.drawLine(
      Offset(cropBoxRect.left, cropBoxRect.top + hThird * 2),
      Offset(cropBoxRect.right, cropBoxRect.top + hThird * 2),
      gridPaint,
    );

    // 4. 四个角落的增强直角角标 (类似专业相机/iOS照片裁剪器)
    final cornerPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    const cornerLen = 16.0;

    // 左上
    canvas.drawLine(cropBoxRect.topLeft, cropBoxRect.topLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(cropBoxRect.topLeft, cropBoxRect.topLeft + const Offset(0, cornerLen), cornerPaint);

    // 右上
    canvas.drawLine(cropBoxRect.topRight, cropBoxRect.topRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(cropBoxRect.topRight, cropBoxRect.topRight + const Offset(0, cornerLen), cornerPaint);

    // 左下
    canvas.drawLine(cropBoxRect.bottomLeft, cropBoxRect.bottomLeft + const Offset(cornerLen, 0), cornerPaint);
    canvas.drawLine(cropBoxRect.bottomLeft, cropBoxRect.bottomLeft + const Offset(0, -cornerLen), cornerPaint);

    // 右下
    canvas.drawLine(cropBoxRect.bottomRight, cropBoxRect.bottomRight + const Offset(-cornerLen, 0), cornerPaint);
    canvas.drawLine(cropBoxRect.bottomRight, cropBoxRect.bottomRight + const Offset(0, -cornerLen), cornerPaint);

    // 5. 若是圆形头像，额外绘制圆形辅助虚线
    if (isCircle) {
      final circlePaint = Paint()
        ..color = const Color(0xFFFF6584).withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      canvas.drawCircle(cropBoxRect.center, cropBoxRect.width / 2, circlePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CropOverlayPainter oldDelegate) {
    return oldDelegate.cropBoxRect != cropBoxRect || oldDelegate.isCircle != isCircle;
  }
}
