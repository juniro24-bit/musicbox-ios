import SwiftUI

enum SortMode: String, CaseIterable, Identifiable {
    case recent = "최근 추가"
    case title = "제목"
    case artist = "아티스트"
    case plays = "많이 들은 순"

    var id: String { rawValue }
}

@MainActor
struct LibraryView: View {
    @EnvironmentObject var library: LibraryStore
    @EnvironmentObject var player: PlayerService

    var goImport: () -> Void

    @State private var query = ""
    @State private var onlyFavorites = false
    @State private var sort: SortMode = .recent
    @State private var deleting: Track?
    @State private var editingInfo: Track?
    @State private var trimming: Track?

    private func artistKey(_ track: Track) -> String {
        track.artist.isEmpty ? "힣" : track.artist
    }

    private var visible: [Track] {
        var list = library.tracks
        if onlyFavorites {
            list = list.filter { $0.favorite }
        }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter { ($0.title + " " + $0.artist).lowercased().contains(q) }
        }
        switch sort {
        case .recent:
            list.sort { $0.createdAt > $1.createdAt }
        case .title:
            list.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        case .artist:
            list.sort { artistKey($0).localizedCompare(artistKey($1)) == .orderedAscending }
        case .plays:
            list.sort { $0.playCount > $1.playCount }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if library.tracks.isEmpty {
                emptyState
            } else {
                trackList
            }
        }
        .appScreen()
        .confirmationDialog(
            "곡을 삭제할까요?",
            isPresented: Binding(
                get: { deleting != nil },
                set: { if !$0 { deleting = nil } }
            ),
            titleVisibility: .visible,
            presenting: deleting
        ) { track in
            Button("삭제", role: .destructive) {
                performDelete(track)
            }
            Button("취소", role: .cancel) {}
        } message: { track in
            Text("\"\(track.title)\" 파일이 이 폰에서 지워지고 되돌릴 수 없어요.")
        }
        .sheet(item: $editingInfo) { track in
            InfoEditView(track: track) { title, artist in
                var updated = track
                updated.title = title
                updated.artist = artist
                library.update(updated)
                player.trackUpdated(updated)
            }
        }
        .sheet(item: $trimming) { track in
            TrimView(track: track)
        }
    }

    // MARK: 위쪽 (제목, 검색, 필터)

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("라이브러리")
                    .font(Theme.heading(34))
                if !library.tracks.isEmpty {
                    Text("\(library.tracks.count)곡")
                        .font(.system(size: 15).monospacedDigit())
                        .foregroundColor(Theme.muted)
                }
            }
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(Theme.muted)
                TextField("곡이나 아티스트 검색", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.s1)
            )

            HStack {
                filterChip("전체", selected: !onlyFavorites) { onlyFavorites = false }
                filterChip("즐겨찾기", selected: onlyFavorites) { onlyFavorites = true }
                Spacer()
                Menu {
                    Picker("정렬", selection: $sort) {
                        ForEach(SortMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sort.rawValue)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }

    private func filterChip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(selected ? Theme.bg : Theme.muted)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(selected ? Theme.text : Theme.s1))
        }
        .buttonStyle(.plain)
    }

    // MARK: 목록

    private var trackList: some View {
        Group {
            if visible.isEmpty {
                Text(onlyFavorites && query.isEmpty ? "즐겨찾기한 곡이 없어요." : "검색 결과가 없어요.")
                    .font(.system(size: 15))
                    .foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                Spacer()
            } else {
                List {
                    ForEach(visible) { track in
                        TrackRow(
                            track: track,
                            isCurrent: player.current?.id == track.id,
                            isPlaying: player.isPlaying,
                            onTap: { tapped(track) },
                            onFavorite: { toggleFavorite(track) },
                            onInfo: { editingInfo = track },
                            onTrim: { trimming = track },
                            onDelete: { deleting = track }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 4, leading: 18, bottom: 4, trailing: 8))
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deleting = track
                            } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.s1)
                Image(systemName: "music.note")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundColor(Theme.amber)
            }
            .frame(width: 72, height: 72)
            Text("아직 곡이 없어요")
                .font(.system(size: 17, weight: .bold))
            Text("유튜브 링크를 붙여넣어서 첫 곡을 가져와 보세요.")
                .font(.system(size: 14))
                .foregroundColor(Theme.muted)
                .multilineTextAlignment(.center)
            Button("가져오기", action: goImport)
                .buttonStyle(PrimaryButtonStyle())
                .frame(width: 160)
                .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
    }

    // MARK: 동작

    private func tapped(_ track: Track) {
        if player.current?.id == track.id {
            player.togglePlay()
        } else {
            player.play(visible, startAt: track)
        }
    }

    private func toggleFavorite(_ track: Track) {
        if let updated = library.toggleFavorite(id: track.id) {
            player.trackUpdated(updated)
        }
    }

    private func performDelete(_ track: Track) {
        player.trackDeleted(id: track.id)
        library.delete(track)
    }
}

/// 제목, 아티스트 수정 시트
struct InfoEditView: View {
    let track: Track
    var onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var artist: String

    init(track: Track, onSave: @escaping (String, String) -> Void) {
        self.track = track
        self.onSave = onSave
        _title = State(initialValue: track.title)
        _artist = State(initialValue: track.artist)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("제목, 아티스트 수정")
                .font(Theme.heading(22))
                .padding(.top, 24)
            field("제목", text: $title)
            field("아티스트", text: $artist)
            Button("저장") {
                let trimmed = title.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return }
                onSave(trimmed, artist.trimmingCharacters(in: .whitespaces))
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            Spacer()
        }
        .padding(.horizontal, 20)
        .appScreen()
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private func field(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 13))
                .foregroundColor(Theme.muted)
            TextField(label, text: text)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.s1)
                )
        }
    }
}
