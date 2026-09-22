import SwiftUI

struct RemoteAsyncImage: View {
    let urlString: String?
    var placeholderSystemImage = "shippingbox.fill"

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    ProgressView()
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        Image(systemName: placeholderSystemImage)
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.quaternary.opacity(0.4))
    }
}

struct StatusBanner: View {
    @Environment(ClientAppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            if model.isWorking {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: model.statusMessage.contains("无法连接") ? "wifi.slash" : "dot.radiowaves.left.and.right")
                    .foregroundStyle(model.statusMessage.contains("无法连接") ? .orange : .accentColor)
            }
            Text(model.statusMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .lineLimit(2)
            Spacer(minLength: 0)
            if model.presentedError != nil {
                Button {
                    model.dismissPresentedError()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除错误提示")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: Capsule())
        .animation(.snappy, value: model.statusMessage)
        .animation(.snappy, value: model.isWorking)
    }
}

struct CopyableURLRow: View {
    let title: String
    let url: String?

    var body: some View {
        if let url, !url.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(url)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                ShareLink(item: url) {
                    Label("分享订阅地址", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

enum IOSDetailTab: String, CaseIterable, Identifiable {
    case info
    case preview

    var id: String { rawValue }

    var title: String {
        switch self {
        case .info: "详情"
        case .preview: "预览"
        }
    }
}
