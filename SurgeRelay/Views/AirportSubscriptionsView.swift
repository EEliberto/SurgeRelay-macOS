import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AirportSubscriptionsView: View {
    @Environment(AppModel.self) private var model
    @State private var editorRoute: AirportEditorRoute?
    @State private var previewRoute: AirportPreviewRoute?
    @State private var targetEditorRoute: ConfigurationTargetEditorRoute?
    @State private var deleteCandidate: AirportSubscription?
    @State private var refreshingID: UUID?
    @State private var confirmsWrite = false

    private var canWriteConfiguration: Bool {
        let enabled = model.airportSubscriptions.filter { $0.isEnabled && $0.isConfigured }
        return !enabled.isEmpty
            && enabled.allSatisfy { model.hasCachedAirportSubscription(id: $0.id) }
            && model.surgeConfigurationTargets.contains(where: \.isEnabled)
    }

    var body: some View {
        Form {
            Section("机场") {
                if model.airportSubscriptions.isEmpty {
                    ContentUnavailableView {
                        Label {
                            Text("尚未添加机场")
                        } icon: {
                            Image("AirportSubscriptionIcon")
                                .resizable()
                                .frame(width: 44, height: 44)
                        }
                    } actions: {
                        Button("添加机场") { editorRoute = AirportEditorRoute(subscription: nil) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                } else {
                    ForEach(model.airportSubscriptions) { subscription in
                        airportRow(subscription)
                    }
                }
            }

            Section("Surge 配置") {
                ForEach(model.surgeConfigurationTargets) { target in
                    configurationRow(target)
                }

                HStack {
                    Button("添加配置文件") { addConfigurationFiles() }
                    Spacer()
                    Button("写入配置") { confirmsWrite = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!canWriteConfiguration)
                }
            }

            Section("配置预览") {
                WrappingPlainTextView(text: model.airportConfigurationPreview)
                    .frame(minHeight: 420, idealHeight: 520)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("机场订阅汇总")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    editorRoute = AirportEditorRoute(subscription: nil)
                } label: {
                    Label("添加机场", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editorRoute) { route in
            AirportSubscriptionEditor(subscription: route.subscription)
                .environment(model)
        }
        .sheet(item: $previewRoute) { route in
            AirportSubscriptionPreview(subscriptionID: route.subscriptionID)
                .environment(model)
        }
        .sheet(item: $targetEditorRoute) { route in
            ConfigurationTargetEditor(target: route.target)
                .environment(model)
        }
        .confirmationDialog(
            "删除“\(deleteCandidate?.name ?? "")”？",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )
        ) {
            Button("删除机场", role: .destructive) {
                guard let id = deleteCandidate?.id else { return }
                model.removeAirportSubscription(id: id)
                deleteCandidate = nil
            }
            Button("取消", role: .cancel) { deleteCandidate = nil }
        }
        .alert("写入 \(model.surgeConfigurationTargets.filter(\.isEnabled).count) 个配置？", isPresented: $confirmsWrite) {
            Button("取消", role: .cancel) {}
            Button("写入") { writeConfiguration() }
        }
    }

    private func airportRow(_ subscription: AirportSubscription) -> some View {
        HStack(spacing: 12) {
            airportIcon(subscription)
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .opacity(subscription.isEnabled ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 3) {
                Text(subscription.name)
                    .fontWeight(.medium)
                Text(URL(string: subscription.sourceURL)?.host ?? subscription.sourceURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let date = subscription.lastUpdatedAt {
                    Text("链接更新于 \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let error = subscription.lastError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { subscription.isEnabled },
                set: { model.setAirportSubscriptionEnabled(id: subscription.id, enabled: $0) }
            ))
            .labelsHidden()
            Button {
                refresh(subscription.id)
            } label: {
                if refreshingID == subscription.id {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .help("立即拉取并更新缓存")
            .disabled(refreshingID != nil)
            Button {
                previewRoute = AirportPreviewRoute(subscriptionID: subscription.id)
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .help(model.hasCachedAirportSubscription(id: subscription.id) ? "查看缓存内容" : "拉取并预览")
            Button("编辑") { editorRoute = AirportEditorRoute(subscription: subscription) }
            Button(role: .destructive) { deleteCandidate = subscription } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private func airportIcon(_ subscription: AirportSubscription) -> some View {
        if let url = URL(string: subscription.iconURL.trimmingCharacters(in: .whitespacesAndNewlines)),
           !subscription.iconURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Image("AirportSubscriptionIcon").resizable().scaledToFit()
                }
            }
        } else {
            Image("AirportSubscriptionIcon").resizable().scaledToFit()
        }
    }

    private func refresh(_ id: UUID) {
        refreshingID = id
        Task {
            defer { refreshingID = nil }
            do {
                try await model.refreshAirportSubscription(id: id)
            } catch {
                model.presentedError = error.localizedDescription
            }
        }
    }

    private func configurationRow(_ target: SurgeConfigurationTarget) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.url.lastPathComponent)
                    .fontWeight(.medium)
                Text(target.url.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Toggle("启用", isOn: Binding(
                get: { target.isEnabled },
                set: { model.setSurgeConfigurationTargetEnabled(id: target.id, enabled: $0) }
            ))
            .labelsHidden()
            Button("编辑") { targetEditorRoute = ConfigurationTargetEditorRoute(target: target) }
            Button(role: .destructive) { model.removeSurgeConfigurationTarget(id: target.id) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 4)
    }

    private func addConfigurationFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        guard panel.runModal() == .OK else { return }
        model.addSurgeConfigurationTargets(panel.urls)
    }

    private func writeConfiguration() {
        do {
            _ = try model.writeAirportSubscriptionsToEnabledConfigurations()
        } catch {
            model.presentedError = error.localizedDescription
        }
    }
}

private struct AirportEditorRoute: Identifiable {
    let id = UUID()
    let subscription: AirportSubscription?
}

private struct AirportPreviewRoute: Identifiable {
    let id = UUID()
    let subscriptionID: UUID
}

private struct ConfigurationTargetEditorRoute: Identifiable {
    let id = UUID()
    let target: SurgeConfigurationTarget
}

private struct ConfigurationTargetEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let target: SurgeConfigurationTarget
    @State private var path: String
    @State private var errorMessage: String?

    init(target: SurgeConfigurationTarget) {
        self.target = target
        _path = State(initialValue: target.path)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("配置文件", text: $path)
                Button("选择文件…") { chooseFile() }
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("编辑 Surge 配置")
            .frame(minWidth: 520, minHeight: 190)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "conf") ?? .plainText]
        panel.directoryURL = URL(filePath: path).deletingLastPathComponent()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        path = url.path
    }

    private func save() {
        do {
            try model.updateSurgeConfigurationTarget(id: target.id, path: path)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AirportSubscriptionPreview: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subscriptionID: UUID
    @State private var content = ""
    @State private var errorMessage: String?
    @State private var isRefreshing = false

    private var subscription: AirportSubscription? {
        model.airportSubscriptions.first { $0.id == subscriptionID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if content.isEmpty, isRefreshing {
                    ProgressView("正在拉取订阅…")
                } else if content.isEmpty, let errorMessage {
                    ContentUnavailableView(
                        "无法载入预览",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                } else {
                    WrappingPlainTextView(text: content)
                }
            }
            .frame(minWidth: 720, minHeight: 520)
            .navigationTitle(subscription?.name ?? "订阅预览")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let date = subscription?.lastUpdatedAt {
                        Text("缓存于 \(date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(isRefreshing)
                }
            }
        }
        .task {
            if model.hasCachedAirportSubscription(id: subscriptionID) {
                loadCache()
            } else {
                await refresh()
            }
        }
    }

    private func refresh() async {
        isRefreshing = true
        errorMessage = nil
        defer { isRefreshing = false }
        do {
            try await model.refreshAirportSubscription(id: subscriptionID)
            loadCache()
        } catch {
            errorMessage = error.localizedDescription
            // If a refreshed short URL has expired, keep the last successful cache visible.
            loadCache(preservingError: true)
        }
    }

    private func loadCache(preservingError: Bool = false) {
        do {
            content = try model.cachedAirportSubscriptionContent(id: subscriptionID)
        } catch {
            if !preservingError { errorMessage = error.localizedDescription }
        }
    }
}

/// NSTextView handles large emoji-heavy subscriptions much more efficiently
/// than SwiftUI Text with text selection. Non-contiguous layout keeps offscreen
/// lines from being shaped until they are needed.
private struct WrappingPlainTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = NSTextView(frame: .zero)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false
        textView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: scrollView.contentSize.width,
            height: .greatestFiniteMagnitude
        )
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.string = text
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView,
              textView.string != text else { return }
        let previousSelection = textView.selectedRange()
        textView.string = text
        let textLength = (text as NSString).length
        let location = min(previousSelection.location, textLength)
        let length = min(previousSelection.length, textLength - location)
        textView.setSelectedRange(NSRange(location: location, length: length))
    }
}

private struct AirportSubscriptionEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let subscription: AirportSubscription?
    @State private var draft: AirportSubscriptionDraft
    @State private var errorMessage: String?

    init(subscription: AirportSubscription?) {
        self.subscription = subscription
        _draft = State(initialValue: subscription.map(AirportSubscriptionDraft.init) ?? AirportSubscriptionDraft())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("机场") {
                    TextField("名称", text: $draft.name, prompt: Text("例如 FlowerCloud"))
                    Toggle("写入 Surge 配置", isOn: $draft.isEnabled)
                }
                Section("订阅") {
                    TextField("订阅链接", text: $draft.sourceURL, prompt: Text("https://…"))
                }
                Section("可选参数") {
                    TextField("节点过滤正则", text: $draft.policyRegexFilter, prompt: Text("例如 ^((?!(Traffic|Expire)).)*$"))
                    TextField("图标地址", text: $draft.iconURL, prompt: Text("https://…"))
                }
                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(subscription == nil ? "添加机场" : "编辑机场")
            .frame(minWidth: 520, minHeight: 390)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func save() {
        do {
            if let subscription {
                try model.updateAirportSubscription(id: subscription.id, from: draft)
            } else {
                try model.addAirportSubscription(from: draft)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
