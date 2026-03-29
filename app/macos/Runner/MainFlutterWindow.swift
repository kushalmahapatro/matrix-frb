import Cocoa
import FlutterMacOS
import desktop_multi_window

/// Flutter master may open extra views (e.g. dialog windows) on the same engine; the engine must
/// have multiview enabled before the first `FlutterViewController` is attached.
/// See: `Multiview can only be enabled before adding any view controllers.`
private extension FlutterEngine {
  func enableMultiViewForEmbedding() {
    let sel = NSSelectorFromString("enableMultiView")
    if responds(to: sel) {
      perform(sel)
    }
  }
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let project = FlutterDartProject()
    let engine = FlutterEngine(name: "main", project: project)
    engine.enableMultiViewForEmbedding()
    _ = engine.run(withEntrypoint: nil)

    let flutterViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }

    super.awakeFromNib()
  }
}
