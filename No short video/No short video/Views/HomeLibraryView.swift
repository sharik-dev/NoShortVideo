//
//  HomeLibraryView.swift
//  No short video
//
//  La bibliothèque ouverte depuis l'accueil : des dossiers plutôt qu'un
//  sélecteur Vidéos / Musique. Deux dossiers fixes — Vidéos et Musique, où
//  atterrit tout ce qui n'est rangé nulle part — et autant de dossiers
//  personnels que l'on veut, qui peuvent mélanger vidéos et morceaux.
//

import Combine
import SwiftUI

// MARK: - Registre des dossiers

/// Les dossiers créés par l'utilisateur, dans l'ordre de création.
///
/// Un dossier n'est à l'origine qu'une étiquette posée sur un élément
/// (`SavedVideo.folder`) : il disparaissait dès qu'on en sortait le dernier
/// élément. Le registre permet d'en créer un vide, puis d'y déplacer des
/// éléments ensuite.
final class LibraryFolderStore: ObservableObject {

    static let shared = LibraryFolderStore()

    private let key = "libraryFolders"
    @Published private(set) var names: [String]

    private init() {
        names = UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    func contains(_ name: String) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    func add(_ name: String) {
        guard !name.isEmpty, !contains(name) else { return }
        names.append(name)
        save()
    }

    func rename(_ old: String, to new: String) {
        guard let i = names.firstIndex(of: old) else { return }
        names[i] = new
        save()
    }

    func remove(_ name: String) {
        names.removeAll { $0 == name }
        save()
    }

    /// Absorbe les dossiers nés avant le registre (étiquettes déjà posées).
    func adopt(_ found: [String]) {
        let missing = found.filter { !names.contains($0) }.sorted()
        guard !missing.isEmpty else { return }
        names.append(contentsOf: missing)
        save()
    }

    private func save() {
        UserDefaults.standard.set(names, forKey: key)
    }
}

// MARK: - Modèle

enum LibraryFolder: Hashable {
    case videos, music
    case custom(String)
}

/// Un élément de bibliothèque et le magasin d'où il vient : un dossier
/// personnel mélange les deux.
struct LibraryEntry: Identifiable {
    enum Kind { case video, music }

    let item: SavedVideo
    let kind: Kind

    var id: String { "\(kind)-\(item.id)" }
    var storage: VideoStorageService { kind == .music ? .music : .shared }
    /// Le dossier fixe où l'élément retourne quand on le sort d'un dossier.
    var home: LibraryFolder { kind == .music ? .music : .videos }
    var folder: LibraryFolder { item.folder.isEmpty ? home : .custom(item.folder) }
}

final class HomeLibraryViewModel: ObservableObject {

    @Published private(set) var entries: [LibraryEntry] = []
    let folders = LibraryFolderStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Les noms vivent dans le registre : la grille doit suivre ses
        // changements comme ceux des éléments.
        folders.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    func load() {
        let videos = VideoStorageService.shared.loadAll().map { LibraryEntry(item: $0, kind: .video) }
        let music  = VideoStorageService.music.loadAll().map { LibraryEntry(item: $0, kind: .music) }
        entries = (videos + music).sorted { $0.item.dateAdded > $1.item.dateAdded }
        folders.adopt(Array(Set(entries.map(\.item.folder).filter { !$0.isEmpty })))
    }

    func entries(in folder: LibraryFolder) -> [LibraryEntry] {
        entries.filter { $0.folder == folder }
    }

    /// Où l'on peut déplacer un élément : son dossier fixe et tous les
    /// dossiers personnels, sauf celui où il est déjà.
    func destinations(for entry: LibraryEntry) -> [LibraryFolder] {
        ([entry.home] + folders.names.map { .custom($0) }).filter { $0 != entry.folder }
    }

    func move(_ entry: LibraryEntry, to folder: LibraryFolder) {
        let name: String
        if case .custom(let n) = folder { name = n } else { name = "" }
        entry.storage.updateFolder(videoId: entry.item.id, folder: name)
        load()
    }

    func delete(_ entry: LibraryEntry) {
        entry.storage.delete(videoId: entry.item.id)
        load()
    }

    /// Nom nettoyé, ou `nil` s'il est vide ou déjà pris.
    func validName(_ raw: String) -> String? {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !folders.contains(name) else { return nil }
        return name
    }

    @discardableResult
    func createFolder(_ raw: String) -> String? {
        guard let name = validName(raw) else { return nil }
        folders.add(name)
        return name
    }

    @discardableResult
    func renameFolder(_ old: String, to raw: String) -> String? {
        guard let name = validName(raw) else { return nil }
        VideoStorageService.shared.renameFolder(from: old, to: name)
        VideoStorageService.music.renameFolder(from: old, to: name)
        folders.rename(old, to: name)
        load()
        return name
    }

    /// Supprime le dossier, pas son contenu : chaque élément retourne dans
    /// Vidéos ou Musique.
    func deleteFolder(_ name: String) {
        VideoStorageService.shared.renameFolder(from: name, to: "")
        VideoStorageService.music.renameFolder(from: name, to: "")
        folders.remove(name)
        load()
    }
}

// MARK: - Apparence partagée

private enum LibraryStyle {
    static let videoAccent  = Color.red
    static let musicAccent  = Color(red: 1, green: 0.18, blue: 0.33)
    static let folderAccent = Color.blue

    static func accent(for folder: LibraryFolder) -> Color {
        switch folder {
        case .videos: return videoAccent
        case .music:  return musicAccent
        case .custom: return folderAccent
        }
    }

    static func icon(for folder: LibraryFolder) -> String {
        switch folder {
        case .videos: return "play.rectangle.fill"
        case .music:  return "music.note"
        case .custom: return "folder.fill"
        }
    }
}

// MARK: - Racine : la grille de dossiers

struct HomeLibraryView: View {

    @Binding var isPresented: Bool
    let onOpenVideo: (SavedVideo) -> Void
    let onOpenTrack: (SavedVideo) -> Void

    @StateObject private var vm = HomeLibraryViewModel()
    @ObservedObject private var downloads = VideoDownloadService.shared
    @ObservedObject private var musicPlayer = OfflineMusicPlayer.shared
    @AppStorage("appLanguage") private var lang: String = "en"

    @State private var path: [LibraryFolder] = []
    @State private var showMusicPlayer = false
    @State private var folderPrompt: FolderPrompt? = nil
    @State private var folderName = ""
    @State private var folderToDelete: String? = nil

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14),
                                    GridItem(.flexible(), spacing: 14)],
                          spacing: 14) {
                    tile(.videos)
                    tile(.music)
                    ForEach(vm.folders.names, id: \.self) { name in
                        tile(.custom(name))
                            .contextMenu {
                                Button {
                                    folderName = name
                                    folderPrompt = .rename(name)
                                } label: {
                                    Label(t("Renommer", "Rename"), systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    folderToDelete = name
                                } label: {
                                    Label(t("Supprimer le dossier", "Delete Folder"), systemImage: "trash")
                                }
                            }
                    }
                    newFolderTile
                }
                .padding(16)
            }
            .background(
                LinearGradient(colors: [Color(.systemBackground), Color.black.opacity(0.3)],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
            .navigationTitle(t("Bibliothèque", "Library"))
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button { askNewFolder() } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .accessibilityLabel(t("Nouveau dossier", "New Folder"))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(t("OK", "Done")) { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
            .navigationDestination(for: LibraryFolder.self) { folder in
                LibraryFolderView(
                    folder: folder,
                    vm: vm,
                    onOpen: open,
                    onFolderGone: { path.removeAll() }
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            MusicMiniBar { showMusicPlayer = true }
                .padding(.bottom, 4)
                .animation(.spring(response: 0.35), value: musicPlayer.current?.id)
        }
        .fullScreenCover(isPresented: $showMusicPlayer) {
            MusicPlayerView()
        }
        .folderNameAlert(prompt: $folderPrompt, name: $folderName, lang: lang) { prompt, name in
            switch prompt {
            case .create:
                vm.createFolder(name)
            case .rename(let old):
                vm.renameFolder(old, to: name)
            }
        }
        .confirmationDialog(
            t("Supprimer « \(folderToDelete ?? "") » ?", "Delete “\(folderToDelete ?? "")”?"),
            isPresented: Binding(get: { folderToDelete != nil },
                                 set: { if !$0 { folderToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(t("Supprimer le dossier", "Delete Folder"), role: .destructive) {
                if let name = folderToDelete { vm.deleteFolder(name) }
                folderToDelete = nil
            }
        } message: {
            Text(t("Son contenu retourne dans Vidéos et Musique.",
                   "Its content goes back to Videos and Music."))
        }
        .onAppear {
            vm.load()
            #if DEBUG
            // `simctl launch … -debugOpenDownloads YES -debugOpenVideosFolder YES`
            if UserDefaults.standard.bool(forKey: "debugOpenVideosFolder") { path = [.videos] }
            #endif
        }
        // Un téléchargement terminé : le badge « Hors ligne » apparaît sans
        // rouvrir (cf. `LibraryView` pour le choix d'`onChange`).
        .onChange(of: downloads.jobs.filter { $0.phase == .finished }.map(\.id)) {
            vm.load()
        }
        .onChange(of: downloads.pending.map(\.id)) {
            vm.load()
        }
    }

    /// Un morceau hors ligne se joue ici même, dans le lecteur façon Spotify,
    /// file = les morceaux du même dossier. Le reste ferme la bibliothèque et
    /// s'ouvre dans son site.
    private func open(_ entry: LibraryEntry, in list: [LibraryEntry]) {
        if entry.kind == .music && entry.item.isOffline {
            musicPlayer.play(entry.item, in: list.filter { $0.kind == .music }.map(\.item))
            showMusicPlayer = true
            return
        }
        isPresented = false
        if entry.kind == .music { onOpenTrack(entry.item) } else { onOpenVideo(entry.item) }
    }

    private func askNewFolder() {
        folderName = ""
        folderPrompt = .create
    }

    private func title(_ folder: LibraryFolder) -> String {
        switch folder {
        case .videos: return t("Vidéos", "Videos")
        case .music:  return t("Musique", "Music")
        case .custom(let name): return name
        }
    }

    private func tile(_ folder: LibraryFolder) -> some View {
        let count = vm.entries(in: folder).count
        let accent = LibraryStyle.accent(for: folder)
        return NavigationLink(value: folder) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: LibraryStyle.icon(for: folder))
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 52, height: 52)
                    .background(accent.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                Spacer(minLength: 0)
                Text(title(folder))
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(t("\(count) élément\(count > 1 ? "s" : "")", "\(count) item\(count == 1 ? "" : "s")"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 130, alignment: .leading)
            .padding(14)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private var newFolderTile: some View {
        Button { askNewFolder() } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 26, weight: .semibold))
                Text(t("Nouveau dossier", "New Folder"))
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 130)
            .padding(14)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(Color(.tertiaryLabel))
            )
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Contenu d'un dossier

private struct LibraryFolderView: View {

    @State var folder: LibraryFolder
    @ObservedObject var vm: HomeLibraryViewModel
    let onOpen: (LibraryEntry, [LibraryEntry]) -> Void
    /// Le dossier affiché vient d'être supprimé : retour à la grille.
    let onFolderGone: () -> Void

    @ObservedObject private var musicPlayer = OfflineMusicPlayer.shared
    @AppStorage("appLanguage") private var lang: String = "en"

    @State private var moving: LibraryEntry? = nil
    @State private var folderPrompt: FolderPrompt? = nil
    @State private var folderName = ""
    /// L'élément à ranger dans le dossier qu'on est en train de créer.
    @State private var pendingMove: LibraryEntry? = nil
    @State private var confirmDelete = false

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    private var customName: String? {
        if case .custom(let name) = folder { return name }
        return nil
    }

    private var title: String {
        switch folder {
        case .videos: return t("Vidéos", "Videos")
        case .music:  return t("Musique", "Music")
        case .custom(let name): return name
        }
    }

    var body: some View {
        let list = vm.entries(in: folder)
        Group {
            if list.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(list) { entry in
                        row(entry, in: list)
                    }
                }
                .listStyle(.plain)
            }
        }
        .background(
            LinearGradient(colors: [Color(.systemBackground), Color.black.opacity(0.3)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if let name = customName {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            folderName = name
                            folderPrompt = .rename(name)
                        } label: {
                            Label(t("Renommer", "Rename"), systemImage: "pencil")
                        }
                        Button(role: .destructive) { confirmDelete = true } label: {
                            Label(t("Supprimer le dossier", "Delete Folder"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .confirmationDialog(
            t("Déplacer vers…", "Move to…"),
            isPresented: Binding(get: { moving != nil }, set: { if !$0 { moving = nil } }),
            titleVisibility: .visible,
            presenting: moving
        ) { entry in
            ForEach(vm.destinations(for: entry), id: \.self) { dest in
                Button(label(dest)) { vm.move(entry, to: dest) }
            }
            Button(t("Nouveau dossier…", "New Folder…")) { askNewFolder(for: entry) }
        }
        .folderNameAlert(prompt: $folderPrompt, name: $folderName, lang: lang) { prompt, name in
            switch prompt {
            case .create:
                if let created = vm.createFolder(name), let entry = pendingMove {
                    vm.move(entry, to: .custom(created))
                }
                pendingMove = nil
            case .rename(let old):
                if let renamed = vm.renameFolder(old, to: name) {
                    folder = .custom(renamed)
                }
            }
        }
        .confirmationDialog(
            t("Supprimer « \(title) » ?", "Delete “\(title)”?"),
            isPresented: $confirmDelete,
            titleVisibility: .visible
        ) {
            Button(t("Supprimer le dossier", "Delete Folder"), role: .destructive) {
                if let name = customName {
                    vm.deleteFolder(name)
                    onFolderGone()
                }
            }
        } message: {
            Text(t("Son contenu retourne dans Vidéos et Musique.",
                   "Its content goes back to Videos and Music."))
        }
    }

    private func row(_ entry: LibraryEntry, in list: [LibraryEntry]) -> some View {
        SavedVideoRow(
            video: entry.item,
            accent: LibraryStyle.accent(for: entry.home),
            isCurrentTrack: entry.kind == .music && musicPlayer.current?.id == entry.item.id,
            showsFolderBadge: false
        )
        .contentShape(Rectangle())
        .onTapGesture { onOpen(entry, list) }
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { vm.delete(entry) } label: {
                Label(t("Supprimer", "Delete"), systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading) {
            Button { moving = entry } label: {
                Label(t("Déplacer", "Move"), systemImage: "folder")
            }
            .tint(LibraryStyle.folderAccent)
        }
        .contextMenu {
            Menu {
                ForEach(vm.destinations(for: entry), id: \.self) { dest in
                    Button { vm.move(entry, to: dest) } label: {
                        Label(label(dest), systemImage: LibraryStyle.icon(for: dest))
                    }
                }
                Divider()
                Button { askNewFolder(for: entry) } label: {
                    Label(t("Nouveau dossier…", "New Folder…"), systemImage: "folder.badge.plus")
                }
            } label: {
                Label(t("Déplacer vers…", "Move to…"), systemImage: "folder")
            }
            Divider()
            Button(role: .destructive) { vm.delete(entry) } label: {
                Label(t("Supprimer", "Delete"), systemImage: "trash")
            }
        }
    }

    private func label(_ folder: LibraryFolder) -> String {
        switch folder {
        case .videos: return t("Vidéos", "Videos")
        case .music:  return t("Musique", "Music")
        case .custom(let name): return name
        }
    }

    private func askNewFolder(for entry: LibraryEntry) {
        pendingMove = entry
        folderName = ""
        folderPrompt = .create
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: customName == nil ? "tray" : "folder")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text(t("Dossier vide", "Empty Folder"))
                .font(.title2.weight(.semibold))
            Text(customName == nil
                 ? t("Appuyez sur le marque-page pendant\nla lecture pour enregistrer.",
                     "Tap the bookmark icon while watching\nto save something here.")
                 : t("Appui long sur une vidéo ou un morceau,\npuis « Déplacer vers… ».",
                     "Long-press a video or a track,\nthen “Move to…”."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Saisie d'un nom de dossier

enum FolderPrompt: Equatable {
    case create
    case rename(String)
}

private extension View {
    /// L'alerte « Nouveau dossier » / « Renommer », partagée par la grille et
    /// le contenu d'un dossier.
    func folderNameAlert(
        prompt: Binding<FolderPrompt?>,
        name: Binding<String>,
        lang: String,
        commit: @escaping (FolderPrompt, String) -> Void
    ) -> some View {
        let fr = lang == "fr"
        let isRename: Bool = { if case .rename = prompt.wrappedValue { return true }; return false }()
        return alert(
            isRename ? (fr ? "Renommer le dossier" : "Rename Folder")
                     : (fr ? "Nouveau dossier" : "New Folder"),
            isPresented: Binding(get: { prompt.wrappedValue != nil },
                                 set: { if !$0 { prompt.wrappedValue = nil } }),
            presenting: prompt.wrappedValue
        ) { current in
            TextField(fr ? "Nom du dossier" : "Folder name", text: name)
            Button(isRename ? (fr ? "Renommer" : "Rename") : (fr ? "Créer" : "Create")) {
                commit(current, name.wrappedValue)
            }
            Button(fr ? "Annuler" : "Cancel", role: .cancel) {}
        }
    }
}
