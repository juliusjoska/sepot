import Flutter
import UIKit

// SDK iOS 27 bez scénového životního cyklu appku nespustí (TN3187). Scéna jen
// ukáže engine, který AppDelegate spustil při startu procesu — viz komentář
// u `AppDelegate.flutterEngine`.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard let windowScene = scene as? UIWindowScene,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else { return }

    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = FlutterViewController(
      engine: appDelegate.flutterEngine, nibName: nil, bundle: nil)
    self.window = window
    window.makeKeyAndVisible()

    // Super podle okna scény přihlásí engine k událostem scény pro pluginy.
    // Musí běžet dřív, než okno dostane i delegát aplikace: našel-li by ho
    // tam, Flutter by ho bral jako starý způsob startu a přesunul do nového okna.
    super.scene(scene, willConnectTo: session, options: connectionOptions)

    // Pluginy, které okno hledají přes delegáta aplikace (local_auth_darwin
    // u dialogu „biometrie není nastavená“), by ho jinak nenašly.
    appDelegate.window = window
  }
}
