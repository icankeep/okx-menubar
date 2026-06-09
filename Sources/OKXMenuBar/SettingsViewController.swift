import AppKit

@MainActor
final class SettingsViewController: NSViewController {
    private let store: MarketStore

    private let apiKeyField = NSTextField()
    private let secretKeyField = NSSecureTextField()
    private let passphraseField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let saveButton = NSButton(title: "保存并刷新", target: nil, action: nil)
    private let displayModeControl = NSSegmentedControl(
        labels: StatusItemDisplayMode.allCases.map(\.title),
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )

    init(store: MarketStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 430))
        view.wantsLayer = true

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -18)
        ])

        root.addArrangedSubview(headerView())
        root.addArrangedSubview(currentConfigView())
        root.addArrangedSubview(displayModeRow())
        root.addArrangedSubview(fieldRow(title: "API Key", field: apiKeyField, pasteAction: #selector(pasteApiKey)))
        root.addArrangedSubview(fieldRow(title: "Secret Key", field: secretKeyField, pasteAction: #selector(pasteSecretKey)))
        root.addArrangedSubview(fieldRow(title: "Passphrase", field: passphraseField, pasteAction: #selector(pastePassphrase)))
        root.addArrangedSubview(helpLabel())
        root.addArrangedSubview(statusLabel)
        root.addArrangedSubview(buttonRow())

        configureFields()
        loadExistingCredentials()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(apiKeyField)
    }

    private func headerView() -> NSView {
        let title = NSTextField(labelWithString: "OKX API 配置")
        title.font = .boldSystemFont(ofSize: 17)

        let subtitle = NSTextField(labelWithString: "用于读取当前合约持仓，建议 API 只开启读取权限。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        return stack
    }

    private func currentConfigView() -> NSView {
        let text: String
        if let credentials = store.currentCredentials {
            text = "当前已配置：\(credentials.maskedApiKey)"
        } else {
            text = "当前未配置 API 凭证"
        }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = store.currentCredentials == nil ? .systemOrange : .systemGreen
        return label
    }

    private func fieldRow(title: String, field: NSTextField, pasteAction: Selector) -> NSView {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.widthAnchor.constraint(equalToConstant: 86).isActive = true

        field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        field.isEditable = true
        field.isSelectable = true
        field.usesSingleLineMode = true
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        field.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let pasteButton = NSButton(title: "粘贴", target: self, action: pasteAction)
        pasteButton.bezelStyle = .rounded

        let row = NSStackView(views: [titleLabel, field, pasteButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 310).isActive = true
        return row
    }

    private func displayModeRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: "状态栏")
        titleLabel.font = .systemFont(ofSize: 12)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.widthAnchor.constraint(equalToConstant: 86).isActive = true

        displayModeControl.target = self
        displayModeControl.action = #selector(changeDisplayMode)
        displayModeControl.selectedSegment = StatusItemDisplayMode.allCases.firstIndex(of: store.statusItemDisplayMode) ?? 0

        let row = NSStackView(views: [titleLabel, displayModeControl])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        displayModeControl.widthAnchor.constraint(equalToConstant: 220).isActive = true
        return row
    }

    private func helpLabel() -> NSView {
        let label = NSTextField(wrappingLabelWithString: "配置会保存到 ~/.okx-menubar.json，文件权限会设置为 600。不要使用带交易或提币权限的 API Key。")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 2
        label.widthAnchor.constraint(equalToConstant: 460).isActive = true
        return label
    }

    private func buttonRow() -> NSView {
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor

        let reloadButton = NSButton(title: "从本地重新加载", target: self, action: #selector(reloadFromDisk))
        let pasteAllButton = NSButton(title: "从剪贴板填充", target: self, action: #selector(fillFromClipboard))
        let cancelButton = NSButton(title: "取消", target: self, action: #selector(cancel))
        saveButton.target = self
        saveButton.action = #selector(save)
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [reloadButton, pasteAllButton, spacer, cancelButton, saveButton])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.widthAnchor.constraint(equalToConstant: 460).isActive = true
        return row
    }

    private func configureFields() {
        apiKeyField.placeholderString = "OKX API Key"
        secretKeyField.placeholderString = "OKX Secret Key"
        passphraseField.placeholderString = "OKX API Passphrase"
    }

    private func loadExistingCredentials() {
        guard let credentials = store.currentCredentials else { return }
        apiKeyField.stringValue = credentials.apiKey
        secretKeyField.stringValue = credentials.secretKey
        passphraseField.stringValue = credentials.passphrase
    }

    @objc private func pasteApiKey() {
        pasteInto(apiKeyField)
    }

    @objc private func pasteSecretKey() {
        pasteInto(secretKeyField)
    }

    @objc private func pastePassphrase() {
        pasteInto(passphraseField)
    }

    @objc private func fillFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            showError("剪贴板为空")
            return
        }

        if let data = text.data(using: .utf8),
           let credentials = try? JSONDecoder().decode(OKXCredentials.self, from: data) {
            apiKeyField.stringValue = credentials.apiKey
            secretKeyField.stringValue = credentials.secretKey
            passphraseField.stringValue = credentials.passphrase
            showInfo("已从 JSON 填充")
            return
        }

        let values = text
            .split(whereSeparator: \.isNewline)
            .map { line in
                line.split(separator: "=", maxSplits: 1).last.map(String.init) ?? String(line)
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard values.count >= 3 else {
            showError("剪贴板需要包含 API Key、Secret Key、Passphrase 三行，或 JSON 配置")
            return
        }
        apiKeyField.stringValue = values[0]
        secretKeyField.stringValue = values[1]
        passphraseField.stringValue = values[2]
        showInfo("已从剪贴板填充")
    }

    @objc private func reloadFromDisk() {
        store.reloadCredentialsFromDisk()
        loadExistingCredentials()
        if store.currentCredentials == nil {
            showError("未找到本地配置")
        } else {
            showInfo("已重新加载本地配置")
        }
    }

    @objc private func changeDisplayMode() {
        let selectedSegment = displayModeControl.selectedSegment
        guard StatusItemDisplayMode.allCases.indices.contains(selectedSegment) else { return }
        store.setStatusItemDisplayMode(StatusItemDisplayMode.allCases[selectedSegment])
        showInfo("状态栏显示已更新")
    }

    @objc private func cancel() {
        closeWindow()
    }

    @objc private func save() {
        do {
            try store.saveCredentials(
                apiKey: apiKeyField.stringValue,
                secretKey: secretKeyField.stringValue,
                passphrase: passphraseField.stringValue
            )
            saveButton.isEnabled = false
            showInfo("已保存，正在刷新持仓…")
            Task { [weak self] in
                guard let self else { return }
                await self.store.refreshAll()
                await MainActor.run {
                    self.closeWindow()
                }
            }
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func pasteInto(_ field: NSTextField) {
        guard let text = NSPasteboard.general.string(forType: .string) else {
            showError("剪贴板为空")
            return
        }
        field.stringValue = text.trimmingCharacters(in: .whitespacesAndNewlines)
        view.window?.makeFirstResponder(field)
    }

    private func showInfo(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.textColor = .systemGreen
    }

    private func showError(_ text: String) {
        statusLabel.stringValue = text
        statusLabel.textColor = .systemRed
    }

    private func closeWindow() {
        view.window?.close()
    }
}
