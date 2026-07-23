import AppKit
import SwiftUI

struct ModuleIconView: View {
    private static let imageCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()

    let module: RelayModule
    var size: CGFloat = 28

    var body: some View {
        Group {
            if let iconURL = module.customIconURL.flatMap(URL.init(string:)) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay { ProgressView().controlSize(.mini) }
                    case let .success(image):
                        moduleImage(image)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else if let image = cachedImage {
                moduleImage(Image(nsImage: image))
            } else if let iconURL = module.iconURL.flatMap(URL.init(string:)) {
                AsyncImage(url: iconURL) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                            .overlay { ProgressView().controlSize(.mini) }
                    case let .success(image):
                        moduleImage(image)
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var cachedImage: NSImage? {
        let url = ModuleIconStore.cachedURL(for: module.id)
        guard let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
              let modifiedAt = values.contentModificationDate,
              let data = try? Data(contentsOf: url) else { return nil }
        let key = "\(module.id.uuidString)-\(modifiedAt.timeIntervalSince1970)" as NSString
        if let cached = Self.imageCache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        Self.imageCache.setObject(image, forKey: key, cost: values.fileSize ?? data.count)
        return image
    }

    private func moduleImage(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.35), in: iconShape)
            .clipShape(iconShape)
            .overlay {
                iconShape
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
            }
    }

    private var placeholder: some View {
        Image(systemName: "shippingbox")
            .font(.system(size: size * 0.48, weight: .regular))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(.quaternary.opacity(0.55), in: iconShape)
    }

    private var iconShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * ModuleIconView.cornerRadiusRatio, style: .continuous)
    }

    /// Continuous-corner ratio calibrated so the transparent corner matches the
    /// app icon artwork (SummaryIcon): at this ratio a `.continuous` rounded rect
    /// reproduces the icon's measured corner extent (316/1024 of the side).
    static let cornerRadiusRatio: CGFloat = 0.26
}

struct RelayCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }
}

struct StatusPill: View {
    let state: ModuleUpdateState

    private var color: Color {
        switch state {
        case .never: .secondary
        case .updating: .blue
        case .current: .green
        case .failed: .red
        }
    }

    var body: some View {
        Label(state.title, systemImage: state == .updating ? "arrow.trianglehead.2.clockwise.rotate.90" : "circle.fill")
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let detail: String
    let systemImage: String
    let tint: Color

    var body: some View {
        RelayCard {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 42, height: 42)
                    .background(tint.opacity(0.14), in: .rect(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 4) {
                    Text(value).font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(title).font(.headline)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct URLCopyButton: View {
    let url: URL
    @State private var copied = false

    var body: some View {
        Button {
            guard !copied else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.absoluteString, forType: .string)
            withAnimation(.snappy) { copied = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.snappy) { copied = false }
            }
        } label: {
            Label(copied ? "已拷贝" : "拷贝地址",
                  systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.bordered)
        .tint(copied ? .green : .accentColor)
    }
}

/// Inline, editable preview of a single module's converted result. Replaces the
/// old preview window; lives in the detail pane's “预览” tab.
struct ModulePreviewPane: View {
    @Environment(AppModel.self) private var model
    let module: RelayModule
    let showsFindBar: Bool
    @State private var text = ""
    @State private var savedText = ""
    @State private var isLoading = true
    @State private var isWriting = false
    @State private var isEditing = false
    @State private var errorMessage: String?
    @State private var showsComparison = false
    @State private var searchText = ""
    @State private var searchCommand = CodeSearchCommand()
    @State private var searchResult = CodeSearchResult()

    private var currentModule: RelayModule {
        model.modules.first(where: { $0.id == module.id }) ?? module
    }

    var body: some View {
        VStack(spacing: 0) {
            if currentModule.hasOverrideConflict {
                HStack(spacing: 10) {
                    Label("上游内容已变化，请确认本地编辑", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Spacer()
                    Button("比较…") { showsComparison = true }
                    Button("保留本地编辑") {
                        Task { await model.acceptOverrideConflict(moduleID: module.id) }
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.08))
                Divider()
            }
            ZStack(alignment: .top) {
                ModuleCodeTextView(
                    text: $text,
                    isEditable: showsFindBar && isEditing && !isLoading,
                    isInteractive: showsFindBar,
                    onActivate: showsFindBar ? { isEditing = true } : nil,
                    modules: [module],
                    selectedModuleID: module.id,
                    searchQuery: showsFindBar ? searchText : "",
                    searchCommand: searchCommand,
                    searchResult: $searchResult,
                    topContentInset: showsFindBar ? 72 : 16
                )
                .ignoresSafeArea(.container, edges: .top)

                if showsFindBar {
                    CodePreviewSearchBar(
                        query: $searchText,
                        result: searchResult,
                        onNavigate: navigateSearch
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
            }

            Divider()
            HStack(spacing: 12) {
                Button("恢复") { restore() }
                    .disabled(!isEditing || isWriting || isLoading)
                if !isLoading, text != savedText {
                    Text("有尚未写入的修改")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button("保存") { write() }
                    .keyboardShortcut("s", modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!isEditing || isWriting || isLoading || text == savedText)
            }
            .padding(12)
        }
        .task(id: "\(module.id.uuidString)-\(currentModule.contentHash ?? "pending")") { await load() }
        .onChange(of: showsFindBar) { _, isActive in
            if !isActive { isEditing = false }
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(isPresented: $showsComparison) {
            OverrideComparisonView(module: currentModule)
                .environment(model)
        }
    }

    private func navigateSearch(_ direction: CodeSearchDirection) {
        searchCommand = CodeSearchCommand(serial: searchCommand.serial + 1, direction: direction)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard await model.hasPreviewContent(for: module) else {
            text = ""
            savedText = ""
            errorMessage = nil
            return
        }
        do {
            let content = try await model.previewContent(for: module)
            text = content
            savedText = content
        } catch {
            errorMessage = "无法预览转换结果：\(error.localizedDescription)"
        }
    }

    private func write() {
        isWriting = true
        Task {
            defer { isWriting = false }
            do {
                try await model.savePreviewContent(text, for: module)
                savedText = text
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restore() {
        isWriting = true
        Task {
            defer { isWriting = false }
            do {
                let restored = try await model.restorePreviewContent(for: module)
                text = restored
                savedText = restored
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct OverrideComparisonView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let module: RelayModule
    @State private var upstream = ""
    @State private var local = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("上游与本地编辑").font(.headline)
                Spacer()
                Button("完成") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding()
            Divider()
            HSplitView {
                comparisonColumn("最新上游", text: upstream)
                comparisonColumn("当前本地编辑", text: local)
            }
        }
        .frame(minWidth: 920, minHeight: 560)
        .task {
            do {
                async let upstreamValue = model.convertedPreviewContent(for: module)
                async let localValue = model.previewContent(for: module)
                (upstream, local) = try await (upstreamValue, localValue)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        .alert("无法载入比较", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) { Button("好", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private func comparisonColumn(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption.weight(.semibold)).padding(10)
            Divider()
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
            }
        }
    }
}

/// Inline, read-only preview of the merged final module.
struct CombinedPreviewPane: View {
    @Environment(AppModel.self) private var model
    let platform: RelayPlatform
    let showsFindBar: Bool
    @State private var text = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var searchCommand = CodeSearchCommand()
    @State private var searchResult = CodeSearchResult()

    private var enabledModules: [RelayModule] {
        model.settings.modules(for: platform, globalModules: model.modules).filter(\.isEnabled)
    }

    private var reloadToken: String {
        enabledModules.map { "\($0.id.uuidString)-\($0.contentHash ?? "")" }.joined()
    }

    var body: some View {
        ZStack(alignment: .top) {
            ModuleCodeTextView(
                text: .constant(text),
                isEditable: false,
                isInteractive: showsFindBar,
                onActivate: nil,
                modules: enabledModules,
                selectedModuleID: nil,
                searchQuery: showsFindBar ? searchText : "",
                searchCommand: searchCommand,
                searchResult: $searchResult,
                topContentInset: showsFindBar ? 72 : 16
            )
            .ignoresSafeArea(.container, edges: .top)

            if showsFindBar {
                CodePreviewSearchBar(
                    query: $searchText,
                    result: searchResult,
                    onNavigate: navigateSearch
                )
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
        }
        .overlay {
            if !isLoading, text.isEmpty {
                ContentUnavailableView("没有可预览的内容", systemImage: "doc.text.magnifyingglass")
            }
        }
        .task(id: reloadToken) { await load() }
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func navigateSearch(_ direction: CodeSearchDirection) {
        searchCommand = CodeSearchCommand(serial: searchCommand.serial + 1, direction: direction)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        guard !enabledModules.isEmpty, await model.hasCombinedPreviewContent(platform: platform) else {
            text = ""
            errorMessage = nil
            return
        }
        do {
            text = try await model.combinedPreviewContent(platform: platform)
        } catch {
            errorMessage = "无法预览最终模块：\(error.localizedDescription)"
        }
    }
}

private enum CodeSearchDirection: Equatable {
    case previous
    case next
}

private struct CodeSearchCommand: Equatable {
    var serial = 0
    var direction: CodeSearchDirection = .next
}

private struct CodeSearchResult: Equatable {
    var current = 0
    var count = 0
}

private struct CodePreviewSearchBar: View {
    @Binding var query: String
    let result: CodeSearchResult
    let onNavigate: (CodeSearchDirection) -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("搜索", text: $query)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .lineLimit(1)
                    .onSubmit { onNavigate(.next) }

                if !query.isEmpty {
                    Text(result.count == 0 ? "无结果" : "\(result.current)/\(result.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .frame(maxWidth: .infinity)
            .contentShape(Capsule())
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            }

            HStack(spacing: 0) {
                Button { onNavigate(.previous) } label: {
                    Image(systemName: "chevron.up")
                        .frame(width: 30, height: 30)
                }
                .disabled(result.count == 0)

                Button { onNavigate(.next) } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 30, height: 30)
                }
                .disabled(result.count == 0)
            }
            .padding(.horizontal, 3)
            .frame(height: 36)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color(nsColor: .separatorColor).opacity(0.18), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ModuleCodeTextView: NSViewRepresentable {
    @Binding var text: String
    let isEditable: Bool
    let isInteractive: Bool
    let onActivate: (() -> Void)?
    let modules: [RelayModule]
    let selectedModuleID: UUID?
    let searchQuery: String
    let searchCommand: CodeSearchCommand
    @Binding var searchResult: CodeSearchResult
    let topContentInset: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        let textView = ActivatingTextView()
        textView.onActivate = onActivate
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.isEditable = isEditable
        textView.isSelectable = isInteractive
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 18, height: topContentInset)
        textView.string = text
        scrollView.documentView = textView
        context.coordinator.textView = textView
        context.coordinator.applyHighlighting(modules: modules, selectedModuleID: selectedModuleID)
        _ = context.coordinator.needsHighlight(text: text, selectedModuleID: selectedModuleID)
        context.coordinator.updateSearch(
            query: searchQuery,
            command: searchCommand,
            result: $searchResult
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? ActivatingTextView else { return }
        textView.isEditable = isEditable
        textView.isSelectable = isInteractive
        textView.onActivate = onActivate
        if textView.textContainerInset.height != topContentInset {
            textView.textContainerInset = NSSize(width: 18, height: topContentInset)
        }
        if textView.string != text {
            context.coordinator.isApplyingUpdate = true
            textView.string = text
            context.coordinator.isApplyingUpdate = false
        }
        // Re-highlighting runs several regex passes over the whole document; only
        // do it when the text or selection actually changed, so unrelated SwiftUI
        // updates (e.g. switching the detail tab) don't trigger a costly re-scan.
        if context.coordinator.needsHighlight(text: textView.string, selectedModuleID: selectedModuleID) {
            context.coordinator.applyHighlighting(modules: modules, selectedModuleID: selectedModuleID)
        }
        context.coordinator.scrollToSelectedModule(selectedModuleID, modules: modules)
        context.coordinator.updateSearch(
            query: searchQuery,
            command: searchCommand,
            result: $searchResult
        )
    }

    private final class ActivatingTextView: NSTextView {
        var onActivate: (() -> Void)?

        override func mouseDown(with event: NSEvent) {
            if !isEditable, isSelectable, onActivate != nil {
                // Enable editing before AppKit processes the click so the first
                // click places the insertion point and accepts text immediately.
                isEditable = true
                onActivate?()
            }
            super.mouseDown(with: event)
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding private var text: String
        weak var textView: NSTextView?
        var isApplyingUpdate = false
        private var lastSelectedModuleID: UUID?
        private var lastHighlightedText: String?
        private var lastHighlightedSelection: UUID?
        private var lastSearchQuery = ""
        private var lastSearchedText = ""
        private var lastSearchCommandSerial = 0
        private var searchRanges: [NSRange] = []
        private var selectedSearchIndex: Int?

        init(text: Binding<String>) {
            _text = text
        }

        /// Returns true (and records the new state) when the text or selection
        /// changed since the last highlight pass; false when nothing changed.
        func needsHighlight(text: String, selectedModuleID: UUID?) -> Bool {
            guard lastHighlightedText != text || lastHighlightedSelection != selectedModuleID else {
                return false
            }
            lastHighlightedText = text
            lastHighlightedSelection = selectedModuleID
            return true
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingUpdate, let textView else { return }
            text = textView.string
        }

        func updateSearch(
            query: String,
            command: CodeSearchCommand,
            result: Binding<CodeSearchResult>
        ) {
            guard let textView else { return }

            if query != lastSearchQuery || textView.string != lastSearchedText {
                lastSearchQuery = query
                lastSearchedText = textView.string
                searchRanges = ranges(of: query, in: textView.string)
                selectedSearchIndex = searchRanges.isEmpty ? nil : 0
                revealSelectedSearchRange(in: textView)
                publishSearchResult(to: result)
            }

            guard command.serial != lastSearchCommandSerial else { return }
            lastSearchCommandSerial = command.serial
            guard !searchRanges.isEmpty else {
                publishSearchResult(to: result)
                return
            }

            let current = selectedSearchIndex ?? 0
            switch command.direction {
            case .previous:
                selectedSearchIndex = (current - 1 + searchRanges.count) % searchRanges.count
            case .next:
                selectedSearchIndex = (current + 1) % searchRanges.count
            }
            revealSelectedSearchRange(in: textView)
            publishSearchResult(to: result)
        }

        private func ranges(of query: String, in text: String) -> [NSRange] {
            guard !query.isEmpty else { return [] }
            let source = text as NSString
            var results: [NSRange] = []
            var searchRange = NSRange(location: 0, length: source.length)
            while searchRange.length > 0 {
                let match = source.range(of: query, options: [.caseInsensitive], range: searchRange)
                guard match.location != NSNotFound else { break }
                results.append(match)
                let nextLocation = NSMaxRange(match)
                guard nextLocation < source.length else { break }
                searchRange = NSRange(location: nextLocation, length: source.length - nextLocation)
            }
            return results
        }

        private func revealSelectedSearchRange(in textView: NSTextView) {
            guard let selectedSearchIndex, searchRanges.indices.contains(selectedSearchIndex) else { return }
            let range = searchRanges[selectedSearchIndex]
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        private func publishSearchResult(to binding: Binding<CodeSearchResult>) {
            let value = CodeSearchResult(
                current: selectedSearchIndex.map { $0 + 1 } ?? 0,
                count: searchRanges.count
            )
            guard binding.wrappedValue != value else { return }
            DispatchQueue.main.async {
                binding.wrappedValue = value
            }
        }

        func applyHighlighting(modules: [RelayModule], selectedModuleID: UUID?) {
            guard let textStorage = textView?.textStorage else { return }
            let string = textStorage.string
            let fullRange = NSRange(location: 0, length: (string as NSString).length)
            guard fullRange.length > 0 else { return }

            textStorage.beginEditing()
            textStorage.setAttributes([
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor,
                .backgroundColor: NSColor.clear,
            ], range: fullRange)

            apply(pattern: #"^(?:#|//|;).*$"#, options: [.anchorsMatchLines], attributes: [
                .foregroundColor: NSColor.secondaryLabelColor,
            ], to: textStorage)
            apply(pattern: #"^\[[^\n]+\]$"#, options: [.anchorsMatchLines], attributes: [
                .foregroundColor: NSColor.systemPurple,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            ], to: textStorage)
            apply(pattern: #"^#![^\n]*"#, options: [.anchorsMatchLines], attributes: [
                .foregroundColor: NSColor.systemTeal,
            ], to: textStorage)
            apply(pattern: #"https?://[^\s,\"]+"#, attributes: [
                .foregroundColor: NSColor.systemOrange,
            ], to: textStorage)

            applyModuleColors(
                modules: modules,
                selectedModuleID: selectedModuleID,
                textStorage: textStorage
            )
            textStorage.endEditing()
        }

        func scrollToSelectedModule(_ id: UUID?, modules: [RelayModule]) {
            guard let id, id != lastSelectedModuleID, let textView,
                  let module = modules.first(where: { $0.id == id }) else { return }
            lastSelectedModuleID = id
            let key = ModuleMerger.toggleKey(for: module)
            let nsString = textView.string as NSString
            var range = nsString.range(of: "%\(key)%")
            if range.location == NSNotFound { range = nsString.range(of: key) }
            if range.location != NSNotFound {
                textView.scrollRangeToVisible(range)
                textView.setSelectedRange(range)
            }
        }

        private func applyModuleColors(
            modules: [RelayModule],
            selectedModuleID: UUID?,
            textStorage: NSTextStorage
        ) {
            let palette: [NSColor] = [.systemBlue, .systemPurple, .systemOrange, .systemGreen, .systemPink, .systemTeal]
            let colors = Dictionary(uniqueKeysWithValues: modules.enumerated().map {
                (ModuleMerger.toggleKey(for: $0.element), palette[$0.offset % palette.count])
            })
            let selectedKey = selectedModuleID
                .flatMap { id in modules.first(where: { $0.id == id }) }
                .map { ModuleMerger.toggleKey(for: $0) }
            for (key, color) in colors {
                apply(
                    pattern: "^%\(NSRegularExpression.escapedPattern(for: key))%.*$",
                    options: [.anchorsMatchLines],
                    attributes: [
                        .foregroundColor: color,
                        .backgroundColor: color.withAlphaComponent(key == selectedKey ? 0.16 : 0.06),
                    ],
                    to: textStorage
                )
            }
        }

        private func apply(
            pattern: String,
            options: NSRegularExpression.Options = [],
            attributes: [NSAttributedString.Key: Any],
            to textStorage: NSTextStorage
        ) {
            guard let expression = try? NSRegularExpression(pattern: pattern, options: options) else { return }
            let string = textStorage.string
            let range = NSRange(location: 0, length: (string as NSString).length)
            for match in expression.matches(in: string, range: range) {
                textStorage.addAttributes(attributes, range: match.range)
            }
        }
    }
}
