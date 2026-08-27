import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/token_storage.dart';

/// A [CachedNetworkImage] that sends the session bearer token.
///
/// Document images are served from `GET /documents/{id}/file` and
/// `…/attachments/{id}/file`, which sit behind `auth:sanctum` — an
/// unauthenticated fetch answers 401 and the image renders as broken. The
/// token is read from secure storage on mount rather than being passed down
/// through every widget that shows a picture, so a caller only needs the URL.
///
/// Nothing is requested until the token has been read: firing the request
/// first and adding the header later would spend the attempt on a guaranteed
/// 401, and `CachedNetworkImage` would cache that failure against the URL.
class AuthedNetworkImage extends ConsumerStatefulWidget {
  const AuthedNetworkImage({
    super.key,
    required this.url,
    this.fit,
    this.placeholder,
    this.errorWidget,
  });

  final String url;
  final BoxFit? fit;

  /// Shown while the token is being read and while the image loads.
  final Widget? placeholder;

  /// Shown when the fetch fails — including when there is no session at all.
  final Widget? errorWidget;

  @override
  ConsumerState<AuthedNetworkImage> createState() => _AuthedNetworkImageState();
}

class _AuthedNetworkImageState extends ConsumerState<AuthedNetworkImage> {
  String? _token;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _readToken();
  }

  Future<void> _readToken() async {
    String? token;
    try {
      token = await ref.read(tokenStorageProvider).read();
    } catch (_) {
      // Unreadable secure storage is handled the same as no session: the
      // request is not sent and the caller's error widget is shown.
      token = null;
    }
    if (!mounted) return;
    setState(() {
      _token = token;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    final token = _token;
    if (token == null || token.isEmpty) {
      return widget.errorWidget ?? const SizedBox.shrink();
    }

    return CachedNetworkImage(
      imageUrl: widget.url,
      httpHeaders: {'Authorization': 'Bearer $token'},
      fit: widget.fit,
      placeholder: (_, __) => widget.placeholder ?? const SizedBox.shrink(),
      errorWidget: (_, __, ___) =>
          widget.errorWidget ?? const SizedBox.shrink(),
    );
  }
}
