//
//  LibraryView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

struct LibraryView: View {

    // Le même écran sert la bibliothèque vidéo et la bibliothèque musicale :
    // seuls changent le magasin, l'accent, le titre et ce que fait un appui sur
    // une ligne. Dupliquer la vue aurait fait diverger les deux au premier
    // correctif.
    @StateObject private var libraryVM: LibraryViewModel
    @Binding var isPresented: Bool

    private let navigationTitle: String
    private let accent: Color
    private let emptyTitle: (fr: String, en: String)
    private let emptyHint: (fr: String, en: String)
    private let emptyIcon: String
    /// `.mp3` : bibliothèque musicale, dont les morceaux se jouent sur place.
    private let downloadFormat: DownloadFormat
    private let onOpen: (SavedVideo) -> Void

    init(
        isPresented: Binding<Bool>,
        storage: VideoStorageService = .shared,
        navigationTitle: String = "Library",
        accent: Color = .red,
        emptyTitle: (fr: String, en: String) = ("Aucun favori", "No Saved Videos"),
        emptyHint: (fr: String, en: String) = (
            "Appuyez sur le marque-page pendant\nla lecture pour enregistrer.",
            "Tap the bookmark icon while watching\na video to save it here."
        ),
        emptyIcon: String = "bookmark.slash",
        downloadFormat: DownloadFormat = .mp4,
        onOpen: @escaping (SavedVideo) -> Void
    ) {
        _isPresented = isPresented
        _libraryVM = StateObject(wrappedValue: LibraryViewModel(storage: storage))
        self.navigationTitle = navigationTitle
        self.accent = accent
        self.emptyTitle = emptyTitle
        self.emptyHint = emptyHint
        self.emptyIcon = emptyIcon
        self.downloadFormat = downloadFormat
        self.onOpen = onOpen
    }

    @AppStorage("appLanguage") private var lang: String = "en"
    @ObservedObject private var downloads = VideoDownloadService.shared

    @State private var showNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var folderTargetVideoId: String? = nil
    /// Lecteur plein écran des MP3 (bibliothèque musicale).
    @State private var showMusicPlayer = false
    @ObservedObject private var musicPlayer = OfflineMusicPlayer.shared

    /// Bibliothèque musicale : un MP3 téléchargé se joue ici même, dans le
    /// lecteur façon Spotify, sans fermer la liste.
    private var playsMusicInline: Bool { downloadFormat == .mp3 }

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [Color(.systemBackground), Color.black.opacity(0.3)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    if !libraryVM.allFolders.isEmpty {
                        folderFilterBar
                    }
                    if libraryVM.videos.isEmpty {
                        emptyState
                    } else {
                        videoList
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if playsMusicInline {
                    MusicMiniBar { showMusicPlayer = true }
                        .padding(.bottom, 4)
                        .animation(.spring(response: 0.35), value: musicPlayer.current?.id)
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { isPresented = false }
                        .fontWeight(.semibold)
                }
            }
            .alert(t("Nouveau dossier", "New Folder"), isPresented: $showNewFolderAlert) {
                TextField(t("Nom du dossier", "Folder name"), text: $newFolderName)
                Button(t("Créer", "Create")) { commitNewFolder() }
                Button(t("Annuler", "Cancel"), role: .cancel) { newFolderName = "" }
            } message: {
                Text(t("Donnez un nom à votre dossier.", "Give your folder a name."))
            }
        }
        .fullScreenCover(isPresented: $showMusicPlayer) {
            MusicPlayerView()
        }
        .onAppear { libraryVM.load() }
        // Un téléchargement qui se termine pendant qu'on regarde la liste :
        // la ligne prend son badge « Hors ligne » sans avoir à rouvrir.
        //
        // `onChange` et non `onReceive(downloads.$jobs.map…)` : ce dernier
        // recrée l'abonnement à chaque rendu, qui réémet aussitôt, recharge la
        // liste, redessine… une boucle infinie qui figeait l'app.
        .onChange(of: downloads.jobs.filter { $0.phase == .finished }.map(\.id)) {
            libraryVM.load()
        }
        // Une demande de téléchargement crée sa ligne « En attente » ; une
        // annulation peut la retirer.
        .onChange(of: downloads.pending.map(\.id)) {
            libraryVM.load()
        }
    }

    // MARK: - Folder Filter

    private var folderFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                folderChip(label: t("Tous", "All"), value: nil, system: "tray.full")
                ForEach(libraryVM.allFolders, id: \.self) { f in
                    folderChip(label: f, value: f, system: "folder.fill")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    private func folderChip(label: String, value: String?, system: String) -> some View {
        Button { libraryVM.selectedFolder = value } label: {
            HStack(spacing: 5) {
                Image(systemName: system).font(.caption2)
                Text(label).font(.caption).fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(libraryVM.selectedFolder == value ? accent : Color(.systemGray5))
            .foregroundStyle(libraryVM.selectedFolder == value ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: emptyIcon)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(t(emptyTitle.fr, emptyTitle.en))
                .font(.title2)
                .fontWeight(.semibold)

            Text(t(emptyHint.fr, emptyHint.en))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .frame(maxHeight: .infinity)
    }

    // MARK: - Video List

    private var videoList: some View {
        List {
            ForEach(libraryVM.filteredVideos) { video in
                videoRow(video)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if playsMusicInline && video.isOffline {
                            musicPlayer.play(video, in: libraryVM.filteredVideos)
                            showMusicPlayer = true
                        } else {
                            onOpen(video)
                            isPresented = false
                        }
                    }
                    .listRowBackground(Color.clear)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            libraryVM.delete(video: video)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .contextMenu {
                        folderMenu(for: video)
                        Divider()
                        Button(role: .destructive) {
                            libraryVM.delete(video: video)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }
        }
        .listStyle(.plain)
    }

    @ViewBuilder
    private func folderMenu(for video: SavedVideo) -> some View {
        Menu {
            Button {
                folderTargetVideoId = video.id
                newFolderName = ""
                showNewFolderAlert = true
            } label: {
                Label(t("Nouveau dossier…", "New folder…"), systemImage: "folder.badge.plus")
            }

            if !libraryVM.allFolders.isEmpty {
                Divider()
                ForEach(libraryVM.allFolders, id: \.self) { f in
                    Button {
                        libraryVM.setFolder(f, for: video)
                    } label: {
                        if video.folder == f {
                            Label(f, systemImage: "checkmark")
                        } else {
                            Label(f, systemImage: "folder")
                        }
                    }
                }
            }

            if !video.folder.isEmpty {
                Divider()
                Button(role: .destructive) {
                    libraryVM.setFolder("", for: video)
                } label: {
                    Label(t("Retirer du dossier", "Remove from folder"), systemImage: "folder.badge.minus")
                }
            }
        } label: {
            Label(t("Dossier", "Folder"), systemImage: "folder")
        }
    }

    private func commitNewFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { newFolderName = ""; folderTargetVideoId = nil }
        guard !trimmed.isEmpty, let id = folderTargetVideoId else { return }
        guard let video = libraryVM.videos.first(where: { $0.id == id }) else { return }
        LibraryFolderStore.shared.add(trimmed)
        libraryVM.setFolder(trimmed, for: video)
        libraryVM.selectedFolder = trimmed
    }

    // MARK: - Video Row

    private func videoRow(_ video: SavedVideo) -> some View {
        SavedVideoRow(
            video: video,
            accent: accent,
            isCurrentTrack: playsMusicInline && musicPlayer.current?.id == video.id
        )
    }
}

// MARK: - Ligne

/// Une ligne de bibliothèque — miniature, dossier, progression et lecture.
///
/// Rien n'y dit si l'élément est téléchargé, ni s'il est en train de l'être :
/// les favoris musicaux se téléchargent seuls, en silence (cf.
/// `VideoDownloadService.downloadDueFavorites`). Les builds DEBUG gardent
/// l'ancien affichage — ⬇︎, statut, « Hors ligne » — pour l'usage perso.
/// Partagée par `LibraryView` et les dossiers de l'accueil, qui mélangent
/// vidéos et morceaux.
struct SavedVideoRow: View {
    let video: SavedVideo
    let accent: Color
    /// Le morceau en cours du lecteur MP3 : marqué d'une onde.
    let isCurrentTrack: Bool
    /// Inutile dans la vue d'un dossier : on sait déjà où l'on est.
    var showsFolderBadge: Bool = true

    @AppStorage("appLanguage") private var lang: String = "en"
    @ObservedObject private var musicPlayer = OfflineMusicPlayer.shared
    #if DEBUG
    @ObservedObject private var downloads = VideoDownloadService.shared
    private var downloadFormat: DownloadFormat {
        video.url.contains("music.youtube.com") ? .mp3 : .mp4
    }
    #endif

    private func t(_ fr: String, _ en: String) -> String { lang == "fr" ? fr : en }

    var body: some View {
        HStack(spacing: 14) {
            thumbnail(for: video)
            .frame(width: 130, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    #if DEBUG
                    if VideoDownloadService.showsManualDownloads, !video.isOffline, downloads.isPending(video.id) {
                        pendingBadge(for: video)
                    }
                    if VideoDownloadService.showsManualDownloads, video.isOffline {
                        Label(t("Hors ligne", "Offline"), systemImage: "arrow.down.circle.fill")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.18))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                    }
                    #endif
                    if showsFolderBadge && !video.folder.isEmpty {
                        Label(video.folder, systemImage: "folder.fill")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(accent.opacity(0.18))
                            .foregroundStyle(accent)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(video.formattedLastTime) / \(video.formattedDuration)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(.systemGray5))
                            .frame(height: 3)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(accent)
                            .frame(width: geo.size.width * video.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer(minLength: 0)

            #if DEBUG
            if VideoDownloadService.showsManualDownloads, !video.isOffline {
                if downloads.isPending(video.id), downloads.job(for: video.id) == nil {
                    waitingButton(for: video)
                } else {
                    downloadButton(for: video)
                }
            }
            #endif

            // Le morceau en cours est marqué d'une onde, comme dans Spotify.
            Image(systemName: isCurrentTrack ? "waveform" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(accent)
                .symbolEffect(.variableColor.iterative, isActive: isCurrentTrack && musicPlayer.isPlaying)
        }
        .padding(.vertical, 6)
    }

    #if DEBUG
    /// « En attente » tant que son tour n'est pas venu, « Préparation » pendant
    /// la conversion, « 42 % » pendant que le fichier arrive.
    private func pendingBadge(for video: SavedVideo) -> some View {
        let job = downloads.job(for: video.id)
        let label = job.map {
            $0.phase == .downloading
                ? t("\(Int(($0.progress * 100).rounded())) %", "\(Int(($0.progress * 100).rounded()))%")
                : t("Préparation", "Preparing")
        } ?? t("En attente", "Pending")
        return HStack(spacing: 4) {
            Image(systemName: job == nil ? "clock" : "arrow.down.circle")
            Text(label).lineLimit(1)
        }
            .layoutPriority(1)
            .font(.caption2.monospacedDigit())
            .fontWeight(.semibold)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.18))
            .foregroundStyle(.orange)
            .clipShape(Capsule())
    }

    /// Horloge d'une demande qui attend son tour (ou le retour dans l'app,
    /// après une coupure). Un appui propose de l'annuler.
    private func waitingButton(for video: SavedVideo) -> some View {
        Menu {
            Button(role: .destructive) {
                VideoDownloadService.shared.cancel(video.id)
            } label: {
                Label(t("Annuler le téléchargement", "Cancel Download"), systemImage: "xmark.circle")
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title3)
                .foregroundStyle(.orange)
                .padding(6)
        }
        .buttonStyle(.borderless)
    }

    /// ⬇︎ à côté du bouton lecture ; devient un anneau de progression pendant
    /// le téléchargement. `.borderless` : sans lui, un appui sur ce bouton
    /// déclencherait aussi l'ouverture de la ligne.
    @ViewBuilder
    private func downloadButton(for video: SavedVideo) -> some View {
        if let job = downloads.job(for: video.id) {
            ZStack {
                Circle().stroke(Color(.systemGray4), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: max(0.04, job.progress))
                    .stroke(accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 22, height: 22)
            .padding(6)
        } else {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                VideoDownloadService.shared.start(
                    videoId: video.id, title: video.title, duration: video.duration,
                    format: downloadFormat
                )
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .padding(6)
            }
            .buttonStyle(.borderless)
            .tint(Color(.secondaryLabel))
        }
    }
    #endif

    /// Miniature locale si la vidéo a été téléchargée (elle doit s'afficher
    /// sans réseau), sinon celle de YouTube.
    @ViewBuilder
    private func thumbnail(for video: SavedVideo) -> some View {
        if let local = video.localThumbnail {
            Image(uiImage: local).resizable().aspectRatio(16 / 9, contentMode: .fill)
        } else {
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                default:
                    thumbnailPlaceholder
                }
            }
        }
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
    }
}
