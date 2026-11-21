import 'package:flutter/material.dart';
import 'package:google_sign_in_web/web_only.dart' as web_only;
import '../core/theme/colors.dart';
import '../core/theme/text_styles.dart';

/// Tombol resmi Google Identity Services untuk Flutter Web.
Widget buildGoogleWebButton({required Future<void> Function() initialize}) {
  return _GoogleWebButtonWrapper(initialize: initialize);
}

class _GoogleWebButtonWrapper extends StatefulWidget {
  final Future<void> Function() initialize;
  const _GoogleWebButtonWrapper({required this.initialize});

  @override
  State<_GoogleWebButtonWrapper> createState() =>
      _GoogleWebButtonWrapperState();
}

class _GoogleWebButtonWrapperState extends State<_GoogleWebButtonWrapper> {
  late Future<void> _initFuture = widget.initialize();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return OutlinedButton(
            onPressed: () => setState(() => _initFuture = widget.initialize()),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: brandNavy,
              side: BorderSide(color: borderColor),
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              'Tombol Google gagal dimuat. Ketuk untuk muat ulang.',
              style: caption.copyWith(color: brandNavy),
              textAlign: TextAlign.center,
            ),
          );
        }
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(color: brandNavy, strokeWidth: 2),
            ),
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxW = constraints.hasBoundedWidth && constraints.maxWidth > 0
                ? constraints.maxWidth
                : 320.0;
            final width = maxW.clamp(200.0, 400.0).toDouble();
            return Center(
              child: web_only.renderButton(
                configuration: web_only.GSIButtonConfiguration(
                  theme: web_only.GSIButtonTheme.outline,
                  size: web_only.GSIButtonSize.large,
                  text: web_only.GSIButtonText.continueWith,
                  shape: web_only.GSIButtonShape.rectangular,
                  minimumWidth: width,
                  locale: 'id',
                ),
              ),
            );
          },
        );
      },
    );
  }
}
