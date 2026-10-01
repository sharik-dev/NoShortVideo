//
//  OnboardingCaptureTests.swift
//  No short videoUITests
//
//  Captures de l'onboarding et du store que `simctl` ne sait pas faire seul :
//  app en arrière-plan, écran verrouillé, PiP par-dessus l'écran d'accueil.
//  XCUIDevice sait appuyer sur home et sur le bouton latéral, pas simctl.
//
//  Lancé par onboarding-captures/cap-system.sh, qui passe tout par
//  l'environnement (TEST_RUNNER_CAPTURE_*). Sans CAPTURE_DIR, les tests
//  sont ignorés : ils ne tournent jamais par accident.
//

import XCTest

@MainActor
final class OnboardingCaptureTests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
    }

    private func shot(_ name: String) {
        guard let dir = env["CAPTURE_DIR"] else { return }
        let lang = env["CAPTURE_LANG"] ?? "en"
        let url = URL(fileURLWithPath: dir).appendingPathComponent("\(name)_\(lang).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func launch(_ url: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-debugCaptureScript", env["CAPTURE_SCRIPT"] ?? "", "-debugOpenURL", url]
        app.launch()
        return app
    }

    /// Musique lancée, puis l'app quitte l'écran : écran d'accueil, puis
    /// écran verrouillé avec le lecteur d'iOS.
    func testBackgroundAndLock() throws {
        try XCTSkipIf(env["CAPTURE_DIR"] == nil, "capture only")
        _ = launch(env["CAPTURE_MUSIC_URL"] ?? "https://music.youtube.com/watch?v=dQw4w9WgXcQ")
        sleep(26)
        XCUIDevice.shared.press(.home)
        sleep(4)
        shot("sys_home")
        // Premier appui : l'écran s'éteint. Second : il se rallume sur
        // l'écran verrouillé, lecteur en cours.
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        sleep(2)
        XCUIDevice.shared.perform(NSSelectorFromString("pressLockButton"))
        // Le lecteur apparaît après ~2 s, l'écran s'assombrit vers 5 s :
        // plusieurs prises, on garde la meilleure.
        for i in 1...5 {
            Thread.sleep(forTimeInterval: 0.8)
            shot("sys_lock\(i)")
        }
        // Contrôle : 10 s plus tard, le temps écoulé doit avoir avancé.
        sleep(10)
        shot("sys_lock_later")
    }

    /// Le bouton PiP flottant de l'app, puis retour à l'écran d'accueil :
    /// la vidéo continue dans sa fenêtre.
    func testPictureInPicture() throws {
        try XCTSkipIf(env["CAPTURE_DIR"] == nil, "capture only")
        let app = launch(env["CAPTURE_WATCH_URL"] ?? "https://m.youtube.com/watch?v=jNQXAC9IVRw")
        sleep(20)
        shot("sys_pip_before")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.062, dy: 0.768)).tap()
        sleep(4)
        shot("sys_pip_app")
        XCUIDevice.shared.press(.home)
        sleep(4)
        shot("sys_pip_home")
    }
}
