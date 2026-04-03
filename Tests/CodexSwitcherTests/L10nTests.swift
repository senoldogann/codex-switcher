import Foundation
import Testing
@testable import CodexSwitcher

struct L10nTests {
    @Test
    func turkishModeUsesTurkishAutomationStrings() {
        let defaults = UserDefaults.standard
        let previous = defaults.string(forKey: "appLanguage")
        defaults.set("tr", forKey: "appLanguage")
        defer {
            if let previous {
                defaults.set(previous, forKey: "appLanguage")
            } else {
                defaults.removeObject(forKey: "appLanguage")
            }
        }

        #expect(Str.automationConfidence == "Otomasyon güveni")
        #expect(Str.accountsNeedingAttention == "İlgi gereken hesaplar")
        #expect(Str.stale == "Auth sorunu")
        #expect(Str.lastVerified == "Son doğrulama")
        #expect(Str.healthy == "Sağlıklı")
        #expect(Str.attention == "Dikkat")
        #expect(Str.critical == "Kritik")
        #expect(Str.fallbackRestart == "Yeniden başlatma fallback")
        #expect(Str.manualOverride == "Manuel zorla geçiş")
        #expect(Str.deferred == "Ertelendi")
        #expect(Str.inconclusive == "Belirsiz")
        #expect(Str.automationWarningTitle == "Otomasyon dikkat istiyor")
        #expect(Str.automationCriticalTitle == "Otomasyon acil dikkat istiyor")
    }
}
