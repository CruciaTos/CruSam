// lib/features/pdf/widgets/pdf_pages_preview.dart
//
// Shows a PDF exactly as it will be saved: the real document is built and
// every page rasterised, laid out as white sheets at print size (96 px per
// inch). Because previews render the same bytes the export writes, the
// screen can never drift from the file.

import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class PdfPagesPreview extends StatefulWidget {
  /// Builds the document. Called again (debounced) whenever [inputs] change.
  final Future<Uint8List> Function() build;

  /// Everything the document depends on. Compared deeply between rebuilds;
  /// objects without value equality count as changed when replaced.
  final List<Object?> inputs;

  /// Vertical space between sheets.
  final double gap;

  const PdfPagesPreview({
    super.key,
    required this.build,
    required this.inputs,
    this.gap = 24,
  });

  @override
  State<PdfPagesPreview> createState() => _PdfPagesPreviewState();
}

class _PdfPage {
  final PdfRaster raster;
  final double width;
  final double height;
  const _PdfPage(this.raster, this.width, this.height);
}

class _PdfPagesPreviewState extends State<PdfPagesPreview> {
  static const _screenDpi = 96.0;
  static const _debounce = Duration(milliseconds: 250);
  static const _inputsEquality = DeepCollectionEquality();

  List<_PdfPage> _pages = const [];
  Object? _error;
  Timer? _timer;
  int _generation = 0;
  double _pixelRatio = 1;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final first = _generation == 0;
    if (ratio != _pixelRatio || first) {
      _pixelRatio = ratio;
      _schedule(immediate: first);
    }
  }

  @override
  void didUpdateWidget(covariant PdfPagesPreview old) {
    super.didUpdateWidget(old);
    if (!_inputsEquality.equals(old.inputs, widget.inputs)) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _schedule({bool immediate = false}) {
    _timer?.cancel();
    if (immediate) {
      _render();
    } else {
      _timer = Timer(_debounce, _render);
    }
  }

  Future<void> _render() async {
    final generation = ++_generation;
    final dpi = _screenDpi * _pixelRatio;
    try {
      final bytes = await widget.build();
      final pages = <_PdfPage>[];
      await for (final raster in Printing.raster(bytes, dpi: dpi)) {
        pages.add(_PdfPage(raster, raster.width / _pixelRatio,
            raster.height / _pixelRatio));
      }
      if (!mounted || generation != _generation) return;
      setState(() {
        _pages = pages;
        _error = null;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null && _pages.isEmpty) {
      return _Sheet(
        width: 793.7,
        height: 400,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Preview failed: $_error',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade700)),
          ),
        ),
      );
    }
    if (_pages.isEmpty) {
      return const _Sheet(
        width: 793.7,
        height: 1122.5,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < _pages.length; i++) ...[
            if (i > 0) SizedBox(height: widget.gap),
            _sheetFor(_pages[i], constraints.maxWidth),
          ],
        ],
      ),
    );
  }

  /// Print size, scaled down (never up) to fit [maxWidth].
  Widget _sheetFor(_PdfPage page, double maxWidth) {
    final scale = maxWidth.isFinite && maxWidth < page.width
        ? maxWidth / page.width
        : 1.0;
    return _Sheet(
      width: page.width * scale,
      height: page.height * scale,
      child: Image(
        image: PdfRasterImage(page.raster),
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
      ),
    );
  }
}

class _Sheet extends StatelessWidget {
  final double width;
  final double height;
  final Widget child;
  const _Sheet({required this.width, required this.height, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: const BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
                color: Color(0x33000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: child,
      );
}
