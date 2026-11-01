import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct ImportView: View {
    @EnvironmentObject var importer: ImportService

    @State private var link = ""
    @State private var showFiles = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("가져오기")
                    .font(Theme.heading(34))
                    .padding(.top, 18)

                VStack(spacing: 12) {
                    HStack(spacing: 6) {
                        TextField("유튜브 링크를 붙여넣으세요", text: $link)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .focused($focused)
                            .onSubmit { startImport() }
                        PasteButton(payloadType: String.self) { strings in
                            if let first = strings.first {
                                link = first
                            }
                        }
                        .labelStyle(.iconOnly)
                        .buttonBorderShape(.capsule)
                        .tint(Theme.s3)
                    }
                    .padding(.leading, 14)
                    .padding(.trailing, 6)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bg)
                    )

                    Button {
                        startImport()
                    } label: {
                        Label("음악으로 가져오기", systemImage: "arrow.down.circle.fill")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.s1)
                )

                Button {
                    showFiles = true
                } label: {
                    Label("내 파일에서 올리기", systemImage: "plus")
                }
                .buttonStyle(GhostButtonStyle())

                ForEach(importer.jobs) { job in
                    JobRow(job: job) { importer.dismiss(job) }
                }

                Text("내가 들을 권리가 있는 영상만 가져오세요. 가져온 곡은 이 폰에만 저장돼요.")
                    .font(.system(size: 13))
                    .foregroundColor(Theme.dim)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .appScreen()
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.audio],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                importer.importFiles(urls)
            }
        }
    }

    private func startImport() {
        let text = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        importer.start(link: text)
        link = ""
        focused = false
    }
}

@MainActor
struct JobRow: View {
    @ObservedObject var job: ImportJob
    var onDismiss: () -> Void

    private var statusText: String {
        switch job.state {
        case .waiting: return "대기 중"
        case .resolving: return "정보를 확인하는 중"
        case .downloading: return "내려받는 중 \(Int(job.progress * 100))%"
        case .processing: return "정리하는 중"
        case .done: return "가져왔어요"
        case .failed: return "실패했어요"
        }
    }

    private var statusColor: Color {
        switch job.state {
        case .done: return Theme.ok
        case .failed: return Theme.danger
        default: return Theme.muted
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(job.title.isEmpty ? job.input : job.title)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Theme.muted)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
            Text(statusText)
                .font(.system(size: 14))
                .foregroundColor(statusColor)

            if job.state == .downloading {
                ProgressView(value: job.progress)
                    .tint(Theme.amber)
            } else if job.state == .resolving || job.state == .processing || job.state == .waiting {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(Theme.amber)
            }

            if job.state == .failed {
                Text(job.message)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.muted)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.s1)
                    )
            }
        }
        .padding(.top, 10)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.s2).frame(height: 1)
        }
    }
}
