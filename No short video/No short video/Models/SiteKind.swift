//
//  SiteKind.swift
//  No short video
//

import Foundation

/// Le site actuellement affiché dans la webview.
///
/// Sert à adapter la barre d'outils : tous les sites n'ont pas besoin des mêmes
/// boutons. Le favori et la bibliothèque ne savent enregistrer qu'une vidéo
/// YouTube (`VideoStorageService` indexe par `?v=`), donc les afficher ailleurs
/// promet une action qui échouerait.
enum SiteKind: String {
    case youtube
    case twitch
    case instagram
    case linkedin
    case x
    case other

    static func detect(_ url: URL?) -> SiteKind {
        guard let host = url?.host?.lowercased() else { return .other }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }

        if on("youtube.com") || on("youtu.be")   { return .youtube }
        if on("twitch.tv")                       { return .twitch }
        if on("instagram.com")                   { return .instagram }
        if on("linkedin.com")                    { return .linkedin }
        if on("x.com") || on("twitter.com")      { return .x }
        return .other
    }

    /// YouTube Music vit dans sa propre webview (cf. `MusicWebViewModel`) :
    /// il faut donc le distinguer du reste de YouTube au moment d'ouvrir un
    /// raccourci, avant même qu'une page soit chargée.
    static func isMusic(_ url: URL?) -> Bool {
        (url?.host?.lowercased() ?? "") == "music.youtube.com"
    }

    /// Nom montré à l'utilisateur — le voile de premier chargement s'en sert.
    var displayName: String {
        switch self {
        case .youtube:   return "YouTube"
        case .twitch:    return "Twitch"
        case .instagram: return "Instagram"
        case .linkedin:  return "LinkedIn"
        case .x:         return "X"
        case .other:     return "Web"
        }
    }

    // MARK: - Barre d'outils

    /// Enregistrer la vidéo en cours — YouTube (et YouTube Music) uniquement.
    var showsBookmark: Bool { self == .youtube }

    /// La bibliothèque ne contient que des vidéos YouTube.
    var showsLibrary: Bool { self == .youtube }

    /// Navigation, rechargement, accueil, réglages et repli : partout.
    var showsNavigation: Bool { true }
}

/// Le compartiment affiché.
///
/// Chacun a sa propre WKWebView, sa propre page et son propre son : passer de
/// l'un à l'autre n'est qu'un changement de visibilité, jamais un chargement
/// par-dessus. C'est ce qui supprime la demi-seconde pendant laquelle on voyait
/// encore le site précédent.
enum BrowserPanel: Equatable {
    case youtube
    case music
    case site(SiteKind)
}
