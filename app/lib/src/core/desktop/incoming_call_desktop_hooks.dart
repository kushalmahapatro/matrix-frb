/// Avoids a dependency cycle: [IncomingCallBannerController] must not import the
/// multi-window opener directly.
Future<void> Function()? _desktopIncomingRingWindowCloser;

void registerDesktopIncomingRingWindowCloser(Future<void> Function()? fn) {
  _desktopIncomingRingWindowCloser = fn;
}

Future<void> closeDesktopIncomingRingWindowIfAny() async {
  await _desktopIncomingRingWindowCloser?.call();
}
