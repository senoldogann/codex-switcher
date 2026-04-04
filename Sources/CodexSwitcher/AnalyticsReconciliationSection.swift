import SwiftUI
import UniformTypeIdentifiers

struct AnalyticsReconciliationSection: View {
    let snapshot: AnalyticsSnapshot
    let foregroundColor: Color
    let exportAction: (_ type: UTType, _ content: @escaping () throws -> String) -> Void

    @State private var selectedEntryID: String?
    @State private var sortOrder: ReconciliationLedgerSortOrder = .highestRisk

    private var state: ReconciliationLedgerSectionState {
        ReconciliationLedgerSectionState(snapshot: snapshot, sortOrder: sortOrder)
    }

    private var selectedEntry: ReconciliationEntry? {
        if let selectedEntryID,
           let selected = state.entries.first(where: { $0.id == selectedEntryID }) {
            return selected
        }
        return state.entries.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if state.isEmpty {
                Text(ReconciliationLedgerPresentation.emptyMessage(for: state))
                    .font(.system(size: 12))
                    .foregroundStyle(foregroundColor.opacity(0.32))
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(cardBackground)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    summaryPills
                    rowList
                    if let selectedEntry {
                        detailCard(for: selectedEntry)
                    }
                }
            }
        }
        .onAppear {
            synchronizeSelection()
        }
        .onChange(of: snapshot.reconciliationEntries.map(\.id)) { _, _ in
            synchronizeSelection()
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Reconciliation ledger", "Reconciliation ledger"))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(foregroundColor.opacity(0.84))
                Text(
                    L(
                        "Provider limit düşüşlerini local usage kanıtı ile pencere bazında açıklar.",
                        "Explains provider-side limit drops against local usage evidence window by window."
                    )
                )
                .font(.system(size: 11))
                .foregroundStyle(foregroundColor.opacity(0.34))
            }

            Spacer()

            Picker(L("Sırala", "Sort"), selection: $sortOrder) {
                ForEach(ReconciliationLedgerSortOrder.allCases) { order in
                    Text(order.title).tag(order)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(foregroundColor.opacity(0.8))

            HStack(spacing: 10) {
                exportButton(title: "CSV", type: .commaSeparatedText) {
                    AnalyticsAuditExporter.buildCSV(for: snapshot.reconciliationEntries)
                }
                exportButton(title: "JSON", type: .json) {
                    try AnalyticsAuditExporter.buildJSON(for: snapshot)
                }
            }
        }
    }

    private var summaryPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(state.summaryItems) { item in
                    HStack(spacing: 6) {
                        Text(item.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(foregroundColor.opacity(0.52))
                        Text("\(item.value)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(toneColor(item.tone).opacity(0.9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(foregroundColor.opacity(0.05)))
                }
            }
        }
    }

    private var rowList: some View {
        LazyVStack(spacing: 10) {
            ForEach(state.entries) { entry in
                Button {
                    selectedEntryID = entry.id
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Circle()
                            .fill(statusColor(entry.status).opacity(entry.status == .ignored ? 0.45 : 0.9))
                            .frame(width: 10, height: 10)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(entry.profileName)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(foregroundColor.opacity(0.82))
                                Text(ReconciliationLedgerPresentation.statusLabel(entry.status))
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(statusColor(entry.status))
                                Spacer()
                                Text(entry.windowEnd.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(foregroundColor.opacity(0.34))
                            }

                            HStack(spacing: 10) {
                                metric(label: L("Haftalık Δ", "Weekly Δ"), value: percentValue(entry.providerWeeklyDeltaPercent))
                                metric(label: L("5h Δ", "5h Δ"), value: percentValue(entry.providerFiveHourDeltaPercent))
                                metric(label: L("Local", "Local"), value: tokenValue(entry.localTokens))
                                metric(label: L("Session", "Sessions"), value: "\(entry.matchedSessionIds.count)")
                                metric(label: L("Reason", "Reason"), value: ReconciliationLedgerPresentation.reasonLabel(entry.reasonCode))
                                metric(label: L("Confidence", "Confidence"), value: ReconciliationLedgerPresentation.confidenceLabel(entry.confidence))
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(rowBackground(for: entry))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(selectedEntryID == entry.id ? statusColor(entry.status).opacity(0.45) : foregroundColor.opacity(0.05), lineWidth: 1)
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func detailCard(for entry: ReconciliationEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L("Seçili pencere", "Selected window"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(foregroundColor.opacity(0.82))
                Spacer()
                Text("\(entry.windowStart.formatted(date: .abbreviated, time: .shortened)) → \(entry.windowEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(foregroundColor.opacity(0.34))
            }

            Text(ReconciliationLedgerPresentation.detailMessage(for: entry))
                .font(.system(size: 11))
                .foregroundStyle(foregroundColor.opacity(0.54))

            if let note = ReconciliationLedgerPresentation.supplementalNote(for: entry) {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundStyle(foregroundColor.opacity(0.36))
            }

            HStack(spacing: 14) {
                metric(label: L("Status", "Status"), value: ReconciliationLedgerPresentation.statusLabel(entry.status))
                metric(label: L("Reason", "Reason"), value: ReconciliationLedgerPresentation.reasonLabel(entry.reasonCode))
                metric(label: L("Confidence", "Confidence"), value: ReconciliationLedgerPresentation.confidenceLabel(entry.confidence))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(L("Matched session IDs", "Matched session IDs"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(foregroundColor.opacity(0.34))
                if entry.matchedSessionIds.isEmpty {
                    Text(L("Bu pencerede session eşleşmesi yok", "No session match in this window"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(foregroundColor.opacity(0.4))
                } else {
                    Text(entry.matchedSessionIds.joined(separator: "\n"))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(foregroundColor.opacity(0.56))
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private func synchronizeSelection() {
        let validIDs = Set(state.entries.map(\.id))
        if let selectedEntryID, validIDs.contains(selectedEntryID) {
            return
        }
        selectedEntryID = state.defaultSelectedEntryID
    }

    private func exportButton(title: String, type: UTType, content: @escaping () throws -> String) -> some View {
        Button {
            exportAction(type, content)
        } label: {
            Label(title, systemImage: "square.and.arrow.up")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor.opacity(0.52))
        }
        .buttonStyle(.plain)
    }

    private func metric(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(foregroundColor.opacity(0.28))
            Text(value)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(foregroundColor.opacity(0.56))
        }
    }

    private func percentValue(_ value: Int?) -> String {
        value.map { "\($0)%" } ?? "—"
    }

    private func tokenValue(_ value: Int) -> String {
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return "\(value)"
    }

    private func toneColor(_ tone: ReconciliationLedgerTone) -> Color {
        switch tone {
        case .explained:
            return .green
        case .weak:
            return .orange
        case .unexplained:
            return .red
        case .idle:
            return .pink
        case .ignored:
            return foregroundColor.opacity(0.5)
        }
    }

    private func statusColor(_ status: ReconciliationStatus) -> Color {
        switch status {
        case .explained:
            return .green
        case .weakAttribution:
            return .orange
        case .unexplained:
            return .red
        case .ignored:
            return foregroundColor.opacity(0.5)
        }
    }

    private func rowBackground(for entry: ReconciliationEntry) -> Color {
        let baseOpacity: Double = selectedEntryID == entry.id ? 0.09 : 0.055
        switch entry.status {
        case .unexplained:
            return Color.red.opacity(baseOpacity)
        case .weakAttribution:
            return Color.orange.opacity(baseOpacity)
        case .explained:
            return foregroundColor.opacity(0.055)
        case .ignored:
            return foregroundColor.opacity(0.03)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(foregroundColor.opacity(0.055))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(foregroundColor.opacity(0.05), lineWidth: 1)
            )
    }
}
