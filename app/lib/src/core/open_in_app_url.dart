import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in an in-app browser (Custom Tabs / SFSafariViewController); on web uses the system handler.
Future<void> openMatrixUrl(BuildContext context, String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;

  var uri = Uri.tryParse(trimmed);
  if (uri == null ||
      (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https'))) {
    uri = Uri.tryParse('https://$trimmed');
  }
  if (uri == null) return;

  try {
    if (!await canLaunchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text('Cannot open this link on this device')),
        );
      }
      return;
    }
    final mode = kIsWeb
        ? LaunchMode.externalApplication
        : LaunchMode.inAppBrowserView;
    await launchUrl(uri, mode: mode);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Could not open link: $e')),
      );
    }
  }
}
