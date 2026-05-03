import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  /// iOS draws the software keyboard with rounded top corners; a few pixels at the
  /// upper-left/right of the keyboard show through to layers below. Using the
  /// storyboard default (white) or a high-contrast app color makes wedges obvious.
  /// Match the system keyboard chrome so those slivers blend in.
  private static let keyboardBackdropColor = UIColor(
    red: 44 / 255,
    green: 44 / 255,
    blue: 46 / 255,
    alpha: 1
  )

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    applyKeyboardBackdropColor(scene)
    // Windows may attach after super returns; cover that pass too.
    DispatchQueue.main.async { [weak self] in
      self?.applyKeyboardBackdropColor(scene)
    }
  }

  private func applyKeyboardBackdropColor(_ scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    for window in windowScene.windows {
      window.backgroundColor = Self.keyboardBackdropColor
    }
  }
}
