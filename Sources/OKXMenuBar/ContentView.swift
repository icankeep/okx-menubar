import SwiftUI

struct ContentView: View {
    @ObservedObject var store: MarketStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            tickerCards
            positionsPanel
            intervalPicker
            contractTabs
            chartArea
            footer
        }
        .padding(16)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: store.selectedContractId) { _ in
            Task { await store.refreshSelectedContractCandles() }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("OKX 合约行情")
                    .font(.title3.bold())
                Text("BTC / ETH / SOL USDT 永续")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var contractTabs: some View {
        Picker("合约", selection: $store.selectedContractId) {
            ForEach(store.snapshots) { snapshot in
                Text(snapshot.contract.symbol).tag(snapshot.contract.id)
            }
        }
        .pickerStyle(.segmented)
    }

    private var tickerCards: some View {
        HStack(spacing: 10) {
            ForEach(store.snapshots) { snapshot in
                TickerCard(snapshot: snapshot)
                    .onTapGesture {
                        store.selectedContractId = snapshot.contract.id
                    }
            }
        }
    }

    private var intervalPicker: some View {
        HStack {
            Text(store.selectedSnapshot?.contract.displayName ?? "--")
                .font(.headline)
            Spacer()
            Picker("周期", selection: $store.selectedInterval) {
                ForEach(CandleInterval.allCases) { interval in
                    Text(interval.title).tag(interval)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
        }
    }

    private var positionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("当前持仓", systemImage: "briefcase")
                    .font(.headline)
                Spacer()
                positionStateText
            }

            switch store.positionState {
            case .notConfigured:
                Text("未配置 OKX API 凭证。配置只读 API 后可查看当前合约持仓。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            case .loading:
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.55)
                    Text("正在加载持仓…")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            case .loaded:
                if store.positions.isEmpty {
                    Text("当前无合约持仓")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(spacing: 6) {
                        ForEach(store.positions) { position in
                            PositionRow(position: position)
                        }
                    }
                }
            case .failed(let message):
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var positionStateText: some View {
        Group {
            switch store.positionState {
            case .notConfigured:
                Text("未配置")
            case .loading:
                Text("刷新中")
            case .loaded(let date):
                Text(date.formatted(date: .omitted, time: .standard))
            case .failed:
                Text("失败")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var chartArea: some View {
        if let snapshot = store.selectedSnapshot {
            let candles = store.selectedInterval == .m15 ? snapshot.candles15m : snapshot.candles4h
            CandlestickChart(candles: candles)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "chart.xyaxis.line")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text("暂无行情")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
                .frame(height: 220)
        }
    }

    private var footer: some View {
        HStack {
            switch store.state {
            case .idle:
                Text("等待刷新")
            case .loading:
                ProgressView().scaleEffect(0.55)
                Text("正在刷新 OKX 数据…")
            case .loaded(let date):
                Text("\(streamStateText) · 更新于 \(date.formatted(date: .omitted, time: .standard))")
            case .failed(let message):
                Text(message).foregroundStyle(.red)
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var streamStateText: String {
        switch store.streamState {
        case .idle: return "WS 未启动"
        case .loading: return "WS 连接中"
        case .streaming: return "WS 实时推送"
        case .reconnecting: return "WS 重连中"
        case .failed(let message): return "WS 失败：\(message)"
        }
    }
}

struct PositionRow: View {
    let position: Position

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(position.symbol)
                    .font(.subheadline.bold())
                Text(position.displaySide)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .foregroundStyle(.white)
                    .background(sideColor)
                    .clipShape(Capsule())
                Text(position.marginMode.uppercased())
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(pnlText)
                    .font(.subheadline.monospacedDigit().bold())
                    .foregroundStyle(pnlColor)
            }

            HStack {
                positionMetric("数量", "\(NumberFormat.volume(abs(position.size))) \(position.symbol)")
                positionMetric("均价", priceText(position.averagePrice))
                positionMetric("标记", priceText(position.markPrice))
                positionMetric("强平", priceText(position.liquidationPrice))
                if let leverage = position.leverage {
                    positionMetric("杠杆", "\(NumberFormat.volume(leverage))x")
                }
            }
        }
        .padding(8)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.38))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sideColor: Color {
        position.isLong ? .red : .green
    }

    private var pnlColor: Color {
        (position.unrealizedPnl ?? 0) >= 0 ? .red : .green
    }

    private var pnlText: String {
        let pnl = position.unrealizedPnl ?? 0
        let ratio = position.unrealizedPnlRatio.map { " \(NumberFormat.percent($0))" } ?? ""
        return "\(pnl >= 0 ? "+" : "")\(NumberFormat.price(pnl))\(ratio)"
    }

    private func priceText(_ value: Double?) -> String {
        guard let value, value > 0 else { return "--" }
        return NumberFormat.price(value)
    }

    private func positionMetric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct TickerCard: View {
    let snapshot: MarketSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(snapshot.contract.symbol)
                    .font(.headline)
                Spacer()
                Text(changeText)
                    .font(.caption.monospacedDigit().bold())
                    .foregroundStyle(changeColor)
            }
            Text(priceText)
                .font(.title3.monospacedDigit().bold())
            HStack {
                Text("H \(highText)")
                Text("L \(lowText)")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            Text("24h Vol \(volumeText)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var priceText: String {
        snapshot.ticker.map { NumberFormat.price($0.last) } ?? "--"
    }

    private var changeText: String {
        snapshot.ticker.map { NumberFormat.percent($0.change24h) } ?? "--"
    }

    private var highText: String {
        snapshot.ticker.map { NumberFormat.price($0.high24h) } ?? "--"
    }

    private var lowText: String {
        snapshot.ticker.map { NumberFormat.price($0.low24h) } ?? "--"
    }

    private var volumeText: String {
        snapshot.ticker.map { NumberFormat.volume($0.volume24h) } ?? "--"
    }

    private var changeColor: Color {
        guard let change = snapshot.ticker?.change24h else { return .secondary }
        return change >= 0 ? .red : .green
    }
}

struct SettingsView: View {
    @ObservedObject var store: MarketStore
    var onClose: () -> Void = {}
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var secretKey = ""
    @State private var passphrase = ""
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("OKX API 配置")
                        .font(.title3.bold())
                    Text("用于读取当前合约持仓，建议只开启读取权限。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    onClose()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
            }

            if let credentials = store.currentCredentials {
                Label("当前已配置：\(credentials.maskedApiKey)", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            } else {
                Label("当前未配置 API 凭证", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 10) {
                field("API Key", text: $apiKey, prompt: "OKX API Key")
                secureField("Secret Key", text: $secretKey, prompt: "OKX Secret Key")
                secureField("Passphrase", text: $passphrase, prompt: "OKX API Passphrase")
            }

            Text("配置会保存到 `~/.okx-menubar.json`，文件权限会设置为 600。请不要使用带交易或提币权限的 API Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(message.hasPrefix("已") ? .green : .red)
            }

            HStack {
                Button("从本地重新加载") {
                    store.reloadCredentialsFromDisk()
                    message = store.currentCredentials == nil ? "未找到本地配置" : "已重新加载本地配置"
                }
                Spacer()
                Button("取消") {
                    onClose()
                    dismiss()
                }
                Button {
                    save()
                } label: {
                    if isSaving {
                        ProgressView().scaleEffect(0.6)
                    } else {
                        Text("保存并刷新")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSaving || apiKey.isEmpty || secretKey.isEmpty || passphrase.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: loadExisting)
    }

    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                TextField(prompt, text: text)
                    .textFieldStyle(.roundedBorder)
                pasteButton(text)
            }
        }
    }

    private func secureField(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack {
                SecureField(prompt, text: text)
                    .textFieldStyle(.roundedBorder)
                pasteButton(text)
            }
        }
    }

    private func pasteButton(_ text: Binding<String>) -> some View {
        Button("粘贴") {
            if let clipboard = NSPasteboard.general.string(forType: .string) {
                text.wrappedValue = clipboard
            }
        }
        .buttonStyle(.bordered)
    }

    private func loadExisting() {
        guard let credentials = store.currentCredentials else { return }
        apiKey = credentials.apiKey
        secretKey = credentials.secretKey
        passphrase = credentials.passphrase
    }

    private func save() {
        isSaving = true
        do {
            try store.saveCredentials(apiKey: apiKey, secretKey: secretKey, passphrase: passphrase)
            message = "已保存，正在刷新持仓…"
            Task {
                await store.refreshAll()
                await MainActor.run {
                    isSaving = false
                    onClose()
                    dismiss()
                }
            }
        } catch {
            message = error.localizedDescription
            isSaving = false
        }
    }
}
