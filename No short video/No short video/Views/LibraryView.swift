//
//  LibraryView.swift
//  No short video
//
//  Created by Sharik Mohamed on 05/03/2026.
//

import SwiftUI

struct LibraryView: View {

    @StateObject private var libraryVM = LibraryViewModel()
    @ObservedObject var youtubeVM: YouTubeWebViewModel
    @Binding var isPresented: Bool

    @AppStorage("appLanguage") private var lang: String = "en"

    @State private var showNewFolderAlert: Bool = false
    @State private var newFolderName: String = ""
    @State private var folderTargetVideoId: String? = nil

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
            .navigationTitle("Library")
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
        .onAppear { libraryVM.load() }
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
            .background(libraryVM.selectedFolder == value ? Color.red : Color(.systemGray5))
            .foregroundStyle(libraryVM.selectedFolder == value ? Color.white : Color.primary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "bookmark.slash")
                .font(.system(size: 60))
                .foregroundStyle(.secondary)

            Text(t("Aucun favori", "No Saved Videos"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(t("Appuyez sur le marque-page pendant\nla lecture pour enregistrer.",
                   "Tap the bookmark icon while watching\na video to save it here."))
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
                        youtubeVM.openVideo(video)
                        isPresented = false
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
        libraryVM.setFolder(trimmed, for: video)
        libraryVM.selectedFolder = trimmed
    }

    // MARK: - Video Row

    private func videoRow(_ video: SavedVideo) -> some View {
        HStack(spacing: 14) {
            AsyncImage(url: URL(string: video.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(16 / 9, contentMode: .fill)
                default:
                    thumbnailPlaceholder
                }
            }
            .frame(width: 130, height: 73)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    if !video.folder.isEmpty {
                        Label(video.folder, systemImage: "folder.fill")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.18))
                            .foregroundStyle(Color.red)
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
                            .fill(Color.red)
                            .frame(width: geo.size.width * video.progress, height: 3)
                    }
                }
                .frame(height: 3)
            }

            Spacer(minLength: 0)

            Image(systemName: "play.circle.fill")
                .font(.title2)
                .foregroundStyle(.red)
        }
        .padding(.vertical, 6)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(.systemGray5))
            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
    }
}
