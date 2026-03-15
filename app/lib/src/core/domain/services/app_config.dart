import 'package:http/http.dart' as http;

enum DataMode { mock, real }

class AppConfig {
  // Environment configuration
  static Uri homeserverUrl = Uri.parse('http://100.112.225.96:6167');
  // static Uri homeserverUrl = Uri.parse('https://matrix.kushalm.xyz');

  // ntfy configuration with DNS fallback options
  static Uri ntfyUrl = Uri.parse(
    'https://ntfy.kushalm.xyz',
  ); // Primary hostname

  // Fallback URLs if primary fails
  static List<Uri> get ntfyFallbackUrls => [
    Uri.parse('https://ntfy.kushalm.xyz'), // Primary
    Uri.parse('https://104.21.51.128'), // IP fallback 1
    Uri.parse('https://172.67.180.155'), // IP fallback 2
    Uri.parse('http://ntfy.kushalm.xyz'), // HTTP fallback
    Uri.parse('http://104.21.51.128'), // HTTP IP fallback
  ];

  static Uri sygnalUrl = Uri.parse('https://sygnal.kushalm.xyz');

  // Data mode configuration for testing
  static DataMode _currentDataMode = DataMode.real;

  /// Get the current data mode
  static DataMode get currentDataMode => _currentDataMode;

  /// Set the data mode (used by integration tests)
  static void setDataMode(DataMode mode) {
    _currentDataMode = mode;
  }

  /// Get the best available ntfy URL by testing connectivity
  static Future<Uri> getBestNtfyUrl() async {
    for (final url in ntfyFallbackUrls) {
      try {
        print('AppConfig: Testing ntfy URL: $url');
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 5));
        if (response.statusCode == 200) {
          print('AppConfig: Found working ntfy URL: $url');
          return url;
        }
      } catch (e) {
        print('AppConfig: ntfy URL $url failed: $e');
        continue;
      }
    }

    // If all fail, return the primary URL
    print('AppConfig: All ntfy URLs failed, using primary: $ntfyUrl');
    return ntfyUrl;
  }
}
