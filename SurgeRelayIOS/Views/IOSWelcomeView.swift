import SwiftUI

struct IOSWelcomeView: View {
    @Environment(ClientAppModel.self) private var model
    @State private var address = ""
    @State private var isWorking = false
    @State private var isTesting = false
    @State private var hasVerified = false
    @State private var errorMessage: String?
    @State private var hasAppeared = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    connectionCard
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(24)
                .padding(.bottom, 40)
            }
            .background(Color(.systemGroupedBackground))
            .safeAreaBar(edge: .bottom) {
                Button {
                    Task { await complete() }
                } label: {
                    Text(isWorking ? "正在进入…" : "开始使用")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .disabled(!hasVerified || isWorking)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .navigationTitle("Surge Relay")
            .navigationBarTitleDisplayMode(.inline)
        }
        .opacity(hasAppeared ? 1 : 0)
        .offset(y: hasAppeared ? 0 : 16)
        .onAppear {
            address = model.ponteServerAddress
            withAnimation(.spring(duration: 0.58, bounce: 0.16)) {
                hasAppeared = true
            }
        }
    }

    private var hero: some View {
        VStack(spacing: 14) {
            BundleImage.image("AppIconDisplay")
                .resizable()
                .scaledToFit()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 18, y: 8)

            Text("连接你的 Mac 服务器")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("在 Mac 上以服务器模式运行 Surge Relay，然后在此输入 Surge Ponte 地址，即可用原生界面远程管理模块。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 12)
    }

    private var connectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Surge Ponte")
                .font(.headline)

            TextField("例如 johnsmac.sgponte", text: $address)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(14)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: address) { _, _ in
                    hasVerified = false
                    errorMessage = nil
                }

            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    if isTesting {
                        ProgressView()
                    }
                    Text(hasVerified ? "已验证连接" : "测试连接")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .disabled(address.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting || isWorking)
        }
        .padding(18)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func testConnection() async {
        errorMessage = nil
        isTesting = true
        defer { isTesting = false }
        do {
            try await model.testPonteConnection(address)
            withAnimation(.snappy) { hasVerified = true }
        } catch {
            hasVerified = false
            errorMessage = error.localizedDescription
        }
    }

    private func complete() async {
        errorMessage = nil
        isWorking = true
        defer { isWorking = false }
        do {
            try await model.completeWelcome(ponteAddress: address)
        } catch {
            errorMessage = error.localizedDescription
            hasVerified = false
        }
    }
}
