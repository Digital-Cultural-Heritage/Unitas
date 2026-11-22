import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class LinkSegment {
  final String text;
  final String? url;

  const LinkSegment({required this.text, this.url});

  bool get isLink => url != null;
}

class LinkableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color linkColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool selectable;
  final TextAlign? textAlign;

  const LinkableText(
    this.text, {
    super.key,
    this.style,
    this.linkColor = const Color(0xFF0B57D0),
    this.maxLines,
    this.overflow,
    this.selectable = true,
    this.textAlign,
  });

  static final RegExp _urlRegex = RegExp(
    r'(?:https?:\/\/|www\.)[^\s<>"{}|\\^\[\]`]+',
    caseSensitive: false,
  );

  static String? normalizeHttpUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final withScheme = trimmed.toLowerCase().startsWith('www.')
        ? 'https://$trimmed'
        : trimmed;
    final uri = Uri.tryParse(withScheme);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if ((scheme != 'http' && scheme != 'https') || uri.host.isEmpty) {
      return null;
    }
    return uri.toString();
  }

  static List<LinkSegment> parseSegments(String text) {
    if (text.isEmpty) return const [];
    final segments = <LinkSegment>[];
    var lastEnd = 0;

    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > lastEnd) {
        segments.add(LinkSegment(text: text.substring(lastEnd, match.start)));
      }

      var rawUrl = match.group(0)!;
      var trailing = '';

      while (rawUrl.isNotEmpty) {
        final lastChar = rawUrl[rawUrl.length - 1];
        if ('.,;:!?'.contains(lastChar)) {
          trailing = lastChar + trailing;
          rawUrl = rawUrl.substring(0, rawUrl.length - 1);
          continue;
        }
        if (lastChar == ')' &&
            '('.allMatches(rawUrl).length < ')'.allMatches(rawUrl).length) {
          trailing = lastChar + trailing;
          rawUrl = rawUrl.substring(0, rawUrl.length - 1);
          continue;
        }
        if (lastChar == ']' &&
            '['.allMatches(rawUrl).length < ']'.allMatches(rawUrl).length) {
          trailing = lastChar + trailing;
          rawUrl = rawUrl.substring(0, rawUrl.length - 1);
          continue;
        }
        break;
      }

      final normalized = normalizeHttpUrl(rawUrl);
      if (normalized != null) {
        segments.add(LinkSegment(text: rawUrl, url: normalized));
      } else {
        segments.add(LinkSegment(text: rawUrl));
      }

      if (trailing.isNotEmpty) {
        segments.add(LinkSegment(text: trailing));
      }

      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      segments.add(LinkSegment(text: text.substring(lastEnd)));
    }

    return segments;
  }

  static List<InlineSpan> buildSpans(
    String text, {
    required TextStyle baseStyle,
    required Color linkColor,
    required void Function(String url) onTapUrl,
    List<TapGestureRecognizer>? recognizers,
  }) {
    final segments = parseSegments(text);
    return segments.map((seg) {
      if (!seg.isLink) {
        return TextSpan(text: seg.text, style: baseStyle);
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () => onTapUrl(seg.url!);
      recognizers?.add(recognizer);
      return TextSpan(
        text: seg.text,
        style: baseStyle.copyWith(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: recognizer,
      );
    }).toList();
  }

  static Future<void> openUrl(BuildContext context, String url) async {
    final normalized = normalizeHttpUrl(url);
    if (normalized == null) return;
    final uri = Uri.parse(normalized);
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && context.mounted) {
        await Clipboard.setData(ClipboardData(text: normalized));
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tidak bisa membuka tautan, disalin ke clipboard'),
            ),
          );
        }
      }
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: normalized));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tidak bisa membuka tautan, disalin ke clipboard'),
          ),
        );
      }
    }
  }

  @override
  State<LinkableText> createState() => _LinkableTextState();
}

class _LinkableTextState extends State<LinkableText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final baseStyle = widget.style ?? DefaultTextStyle.of(context).style;
    final spans = LinkableText.buildSpans(
      widget.text,
      baseStyle: baseStyle,
      linkColor: widget.linkColor,
      onTapUrl: (url) => LinkableText.openUrl(context, url),
      recognizers: _recognizers,
    );

    if (widget.selectable && widget.maxLines == null && widget.overflow == null) {
      return SelectableText.rich(
        TextSpan(children: spans, style: baseStyle),
        textAlign: widget.textAlign,
      );
    }

    return Text.rich(
      TextSpan(children: spans, style: baseStyle),
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}
