import Foundation

enum ReconciliationLedgerSortOrder: String, CaseIterable, Identifiable, Sendable {
    case newest
    case largestProviderDrop
    case highestRisk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newest:
            return L("En yeni", "Newest")
        case .largestProviderDrop:
            return L("En büyük düşüş", "Largest drop")
        case .highestRisk:
            return L("En riskli", "Highest risk")
        }
    }
}

enum ReconciliationLedgerTone: String, Equatable, Sendable {
    case explained
    case weak
    case unexplained
    case idle
    case ignored
}

struct ReconciliationLedgerSummaryItem: Identifiable, Equatable, Sendable {
    let id: String
    let label: String
    let value: Int
    let tone: ReconciliationLedgerTone
}

struct ReconciliationLedgerSectionState: Equatable, Sendable {
    let entries: [ReconciliationEntry]
    let summaryItems: [ReconciliationLedgerSummaryItem]
    let defaultSelectedEntryID: String?

    init(snapshot: AnalyticsSnapshot, sortOrder: ReconciliationLedgerSortOrder) {
        let sortedEntries = ReconciliationLedgerPresentation.sortedEntries(
            snapshot.reconciliationEntries,
            by: sortOrder
        )
        entries = sortedEntries
        summaryItems = ReconciliationLedgerPresentation.summaryItems(
            from: snapshot.reconciliationSummary
        )
        defaultSelectedEntryID = sortedEntries.first?.id
    }

    var isEmpty: Bool {
        entries.isEmpty
    }
}

enum ReconciliationLedgerPresentation {
    static func summaryItems(from summary: ReconciliationSummary) -> [ReconciliationLedgerSummaryItem] {
        [
            ReconciliationLedgerSummaryItem(
                id: "explained",
                label: L("Açıklanmış", "Explained"),
                value: summary.explainedCount,
                tone: .explained
            ),
            ReconciliationLedgerSummaryItem(
                id: "weak",
                label: L("Zayıf", "Weak"),
                value: summary.weakAttributionCount,
                tone: .weak
            ),
            ReconciliationLedgerSummaryItem(
                id: "unexplained",
                label: L("Açıklanamayan", "Unexplained"),
                value: summary.unexplainedCount,
                tone: .unexplained
            ),
            ReconciliationLedgerSummaryItem(
                id: "idle",
                label: "Idle",
                value: summary.idleDrainCount,
                tone: .idle
            ),
            ReconciliationLedgerSummaryItem(
                id: "ignored",
                label: L("Yoksayılmış", "Ignored"),
                value: summary.ignoredCount,
                tone: .ignored
            )
        ]
    }

    static func sortedEntries(
        _ entries: [ReconciliationEntry],
        by sortOrder: ReconciliationLedgerSortOrder
    ) -> [ReconciliationEntry] {
        switch sortOrder {
        case .newest:
            return entries.sorted { lhs, rhs in
                if lhs.windowEnd == rhs.windowEnd {
                    return riskRank(lhs) < riskRank(rhs)
                }
                return lhs.windowEnd > rhs.windowEnd
            }
        case .largestProviderDrop:
            return entries.sorted { lhs, rhs in
                let lhsDrop = max(lhs.providerWeeklyDeltaPercent ?? 0, lhs.providerFiveHourDeltaPercent ?? 0)
                let rhsDrop = max(rhs.providerWeeklyDeltaPercent ?? 0, rhs.providerFiveHourDeltaPercent ?? 0)
                if lhsDrop == rhsDrop {
                    return lhs.windowEnd > rhs.windowEnd
                }
                return lhsDrop > rhsDrop
            }
        case .highestRisk:
            return entries.sorted { lhs, rhs in
                let lhsRisk = riskRank(lhs)
                let rhsRisk = riskRank(rhs)
                if lhsRisk == rhsRisk {
                    return lhs.windowEnd > rhs.windowEnd
                }
                return lhsRisk < rhsRisk
            }
        }
    }

    static func statusLabel(_ status: ReconciliationStatus) -> String {
        switch status {
        case .explained:
            return L("Açıklanmış", "Explained")
        case .weakAttribution:
            return L("Zayıf attribution", "Weak attribution")
        case .unexplained:
            return L("Açıklanamayan", "Unexplained")
        case .ignored:
            return L("Yoksayılmış", "Ignored")
        }
    }

    static func reasonLabel(_ reason: ReconciliationReasonCode) -> String {
        switch reason {
        case .matchedActivity:
            return L("Local aktivite eşleşti", "Matched local activity")
        case .lowLocalUsage:
            return L("Local usage düşük", "Low local usage")
        case .idleDrain:
            return L("Idle drain", "Idle drain")
        case .missingProviderSample:
            return L("Eksik provider örneği", "Missing provider sample")
        case .switchBoundaryOverlap:
            return L("Switch sınırı yakın", "Switch boundary overlap")
        case .belowNoiseFloor:
            return L("Noise floor altında", "Below noise floor")
        case .sampleResetOrCounterJump:
            return L("Sayaç sıçraması / reset", "Counter jump / reset")
        }
    }

    static func confidenceLabel(_ confidence: ReconciliationConfidence) -> String {
        switch confidence {
        case .high:
            return L("Yüksek", "High")
        case .medium:
            return L("Orta", "Medium")
        case .low:
            return L("Düşük", "Low")
        }
    }

    static func detailMessage(for entry: ReconciliationEntry) -> String {
        switch entry.reasonCode {
        case .matchedActivity:
            return L(
                "Provider düşüşü bu penceredeki local aktivite ile tutarlı görünüyor.",
                "The provider-side drop appears consistent with local activity in this window."
            )
        case .lowLocalUsage:
            return L(
                "Local aktivite görüldü ama hacim provider düşüşünü tam açıklamıyor.",
                "Local activity was observed, but its volume does not fully explain the provider drop."
            )
        case .idleDrain:
            return L(
                "Bu pencerede local aktivite görünmüyor; düşüş idle durumda gerçekleşmiş görünüyor.",
                "No local activity was observed in this window; the drop appears to have happened while idle."
            )
        case .missingProviderSample:
            return L(
                "Provider örneği eksik olduğu için bu pencere karar üretmek için güvenilir değil.",
                "This window is not reliable for a decision because the provider sample is incomplete."
            )
        case .switchBoundaryOverlap:
            return L(
                "Aktivite switch sınırına çok yakın; attribution zayıf ama tamamen boş değil.",
                "Activity happened close to the switch boundary, so attribution is weak but not empty."
            )
        case .belowNoiseFloor:
            return L(
                "Düşüş tanımlı noise floor altında kaldığı için pencere bilgi amaçlı tutuldu.",
                "The drop stayed below the configured noise floor, so the window is retained for reference only."
            )
        case .sampleResetOrCounterJump:
            return L(
                "Provider sayaçları yukarı sıçradı veya reset oldu; bu pencere drain kanıtı sayılmadı.",
                "Provider counters jumped upward or reset, so this window was not treated as drain evidence."
            )
        }
    }

    static func supplementalNote(for entry: ReconciliationEntry) -> String? {
        switch entry.reasonCode {
        case .switchBoundaryOverlap:
            return L(
                "Not: event switch anına yakın olduğu için tek pencere attribution’ı düşük güvenle verildi.",
                "Note: the event happened near a switch boundary, so single-window attribution has lower confidence."
            )
        case .missingProviderSample:
            return L(
                "Not: weekly veya 5h örneklerinden biri eksik geldi.",
                "Note: one of the weekly or 5-hour provider samples was missing."
            )
        case .sampleResetOrCounterJump:
            return L(
                "Not: provider kalan yüzdesi önceki örneğe göre yükseldi.",
                "Note: the provider remaining percentage increased compared with the previous sample."
            )
        default:
            return nil
        }
    }

    static func emptyMessage(for state: ReconciliationLedgerSectionState) -> String {
        state.isEmpty
            ? L("Bu aralık için reconciliation penceresi yok", "No reconciliation windows for this range")
            : ""
    }

    private static func riskRank(_ entry: ReconciliationEntry) -> Int {
        switch entry.status {
        case .unexplained:
            return 0
        case .weakAttribution:
            return 1
        case .explained:
            return 2
        case .ignored:
            return 3
        }
    }
}
