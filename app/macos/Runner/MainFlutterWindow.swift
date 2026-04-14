import Cocoa
import FlutterMacOS
import desktop_multi_window
import screen_retriever_macos
import window_manager

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Extra Flutter engines from desktop_multi_window do not run [RegisterGeneratedPlugins];
    // register what auxiliary entrypoints need (window sizing/close + screen metrics).
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      ScreenRetrieverMacosPlugin.register(
        with: controller.registrar(forPlugin: "ScreenRetrieverMacosPlugin"))
      WindowManagerPlugin.register(
        with: controller.registrar(forPlugin: "WindowManagerPlugin"))
    }

    super.awakeFromNib()
  }
}
