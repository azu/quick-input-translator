import SwiftUI
import Translation
import TranslationCore
@preconcurrency import ApplicationServices

@MainActor final class AppModel: ObservableObject {
    @Published var status = "準備画面で権限と言語モデルを確認してください。"
    @Published var shortcutReady = false
    @Published var modelStatus = "未確認"
    @Published var hasPermission = AXIsProcessTrusted()
    @Published var monitorReady = false
    @Published var trigger: TranslationTrigger = TranslationTrigger(
        rawValue: UserDefaults.standard.string(forKey: "translationTrigger") ?? ""
    ) ?? .dots {
        didSet {
            UserDefaults.standard.set(trigger.rawValue, forKey: "translationTrigger")
            onTriggerChange?(trigger)
        }
    }
    var onStatusChange: ((String) -> Void)?
    var onPermissionChange: ((Bool) -> Void)?
    var onTriggerChange: ((TranslationTrigger) -> Void)?

    func setStatus(_ message: String) {
        status = message
        onStatusChange?(message)
    }

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasPermission = AXIsProcessTrustedWithOptions(options)
        onPermissionChange?(hasPermission)
    }

    func refresh() async {
        hasPermission = AXIsProcessTrusted()
        onPermissionChange?(hasPermission)
        switch await LanguageAvailability().status(from: AppleTranslationEngine.source, to: AppleTranslationEngine.target) {
        case .installed: modelStatus = "準備済み"
        case .supported: modelStatus = "ダウンロードが必要"
        case .unsupported: modelStatus = "この環境では利用できません"
        @unknown default: modelStatus = "状態を確認できません"
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: AppModel
    @State private var configuration: TranslationSession.Configuration?
    @State private var preparing = false
    @State private var sample = "この文章を英語に翻訳します。\n次の行はそのまま残します。"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Quick Translate Input").font(.title2.bold())
            Text("日本語 → 英語 · 行末の合図で翻訳")
            Text("日本語を確定し、行末に半角で \(model.trigger.rawValue) を入力すると、その行を翻訳します。Ctrl＋Shift＋Aは行選択だけを行います。翻訳前の行選択は不要です。")
            Picker("翻訳の合図", selection: $model.trigger) {
                ForEach(TranslationTrigger.allCases, id: \.self) { trigger in
                    Text(trigger.rawValue).tag(trigger)
                }
            }
            .pickerStyle(.segmented)

            GroupBox("初回の準備") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("行選択のショートカット: \(model.shortcutReady ? "登録済み" : "未登録")")
                    Text("翻訳の合図の検出: \(model.monitorReady ? "有効" : "権限を許可して状態を再確認してください")")
                    HStack {
                        Text("アクセシビリティ: \(model.hasPermission ? "許可済み" : "未許可")")
                        Spacer()
                        Button("権限を許可") { model.requestPermission() }
                        Button("システム設定を開く") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                    }
                    HStack {
                        Text("言語モデル: \(model.modelStatus)")
                        Spacer()
                        Button(preparing ? "準備中…" : "日本語・英語を準備") {
                            preparing = true
                            if configuration != nil { configuration?.invalidate() }
                            else { configuration = .init(source: AppleTranslationEngine.source, target: AppleTranslationEngine.target) }
                        }
                        .disabled(preparing)
                    }
                    Button("状態を再確認") { Task { await model.refresh() } }
                }
                .padding(6)
            }

            Text(model.status).textSelection(.enabled).frame(minHeight: 36, alignment: .leading)
            Text("テスト用の入力欄").font(.headline)
            TextEditor(text: $sample)
                .font(.body)
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.4))
                .accessibilityLabel("翻訳を試す入力欄")
            Text("他のアプリでも入力欄にカーソルを置いて試せます。必要な入力情報を取得できない欄では中止します。貼り付けの間はクリップボードに訳文を一時保存します。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 620)
        .task { await model.refresh() }
        .translationTask(configuration) { @Sendable session in
            do {
                try await session.prepareTranslation()
                await model.refresh()
                await model.setStatus("言語モデルを準備しました。行末に選択した合図を入力してください。")
            } catch {
                await model.setStatus("言語モデルを準備できませんでした: \(error.localizedDescription)")
            }
            await MainActor.run { preparing = false }
        }
    }
}
