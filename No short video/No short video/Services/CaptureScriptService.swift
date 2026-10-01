//
//  CaptureScriptService.swift
//  No short video
//
//  DEBUG uniquement. Sert à fabriquer les captures de l'onboarding : un
//  script lu sur le disque du Mac (le simulateur y a accès) est injecté dans
//  les webviews, et remplace miniatures et titres par des chats. Tout le
//  reste de la page — et toute l'interface de l'app autour — est le vrai.
//
//  simctl launch … -debugCaptureScript /chemin/absolu/catify.js
//

#if DEBUG
import WebKit

enum CaptureScriptService {
    static func userScript() -> WKUserScript? {
        guard let path = UserDefaults.standard.string(forKey: "debugCaptureScript"),
              let source = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
    }
}
#endif
