class AppConfig {
  // Environment configuration
  // static Uri homeserverUrl = Uri.parse('http://100.112.225.96:6167'); // mac mini synapse
  static Uri homeserverUrl = Uri.parse(
    'https://tuwunel.inve.dev',
  ); // mac mini tuwunel

  static bool proxyEnabled = bool.fromEnvironment('PROXY');

  static String proxyUrl = 'http://10.44.1.85:9090';

  static String? get registrationToken =>
      'WWwFFNPuKQyuAT2PNvji2Xd7fCsezyQmUl7fR/hl3V0=';
}
