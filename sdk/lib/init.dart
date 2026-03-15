import 'package:matrix_sdk/src/bindings/frb_generated.dart';

sealed class MatrixSdk {
  static Future<void> init() async {
    await RustLib.init();
  }
}
