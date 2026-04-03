import Foundation

/// Basit TR/EN yerelleştirme.
/// Önce UserDefaults'taki "appLanguage" key'ine bakar ("tr" / "en" / "system").
/// "system" veya ayarlanmamışsa sistem dilini kullanır.
func L(_ tr: String, _ en: String) -> String {
    let stored = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    let code: String
    if stored == "system" {
        code = Locale.current.language.languageCode?.identifier ?? "en"
    } else {
        code = stored
    }
    return code == "tr" ? tr : en
}

enum Str {
    static var addAccount:   String { L("Hesap Ekle",          "Add Account") }
    static var switchNow:    String { L("Şimdi Geç",           "Switch Now") }
    static var quit:         String { L("Çıkış",               "Quit") }
    static var weekly:       String { L("Haftalık",            "Weekly") }
    static var fiveHour:     String { L("5 Saat",              "5 Hour") }
    static var activeAccount:String { L("Aktif Hesap",         "Active Account") }
    static var noAccounts:   String { L("Hesap eklenmedi",     "No accounts added") }
    static var rename:       String { L("Yeniden Adlandır",    "Rename") }
    static var delete:       String { L("Sil",                 "Delete") }
    static var cancel:       String { L("İptal",               "Cancel") }
    static var save:         String { L("Kaydet",              "Save") }
    static var close:        String { L("Kapat",               "Close") }
    static var start:        String { L("Başlat",              "Start") }
    static var newAccount:   String { L("Yeni Hesap Ekle",     "Add New Account") }
    static var loginWait:    String { L("Login Bekleniyor",    "Waiting for Login") }
    static var detected:     String { L("Hesap Algılandı!",    "Account Detected!") }
    static var added:        String { L("Hesap Eklendi!",      "Account Added!") }
    static var alias:        String { L("Takma ad (opsiyonel)","Alias (optional)") }
    static var aliasPlaceholder: String { L("örn: İş hesabım","e.g. Work account") }
    static var loginDesc:    String { L("Terminal'de `codex login` çalıştırılacak.\nBrowser'da yeni hesabınla giriş yap.",
                                        "Terminal will run `codex login`.\nSign in with your new account in the browser.") }
    static var waitDesc:     String { L("Browser'da hesabınla giriş yap.\nTamamlanınca otomatik devam eder.",
                                        "Sign in with your account in the browser.\nWill continue automatically when done.") }
    static var renameTitle:  String { L("Hesap Adını Değiştir", "Rename Account") }
    static var allExhausted: String { L("Tüm hesaplar doldu!", "All accounts exhausted!") }
    static var switchAnyway: String { L("Yine de geç", "Switch anyway") }
    static var manualOverride: String { L("Manuel zorla geçiş", "Manual override") }
    static var lastKnown:    String { L("son",                 "last") }
    static var unknownUsage: String { L("kullanım bilinmiyor", "usage unknown") }
    static var resets:       String { L("Sıfırlanma",         "Resets") }
    // History
    static var history:      String { L("Geçmiş",             "History") }
    static var noHistory:    String { L("Henüz geçiş yok",    "No switches yet") }
    static var automation:   String { L("Otomasyon",          "Automation") }
    static var switches:     String { L("Geçişler",           "Switches") }
    static var range:        String { L("Aralık",             "Range") }
    static var queued:       String { L("Bekleyen",           "Queued") }
    static var seamless:     String { L("Sessiz geçiş",       "Seamless") }
    static var fallback:     String { L("Fallback",           "Fallback") }
    static var automationConfidence: String { L("Otomasyon güveni", "Automation confidence") }
    static var accountsNeedingAttention: String { L("İlgi gereken hesaplar", "Accounts needing attention") }
    static var stale:        String { L("Auth sorunu",        "Stale") }
    static var lastVerified: String { L("Son doğrulama",      "Last verified") }
    static var healthy:      String { L("Sağlıklı",           "Healthy") }
    static var attention:    String { L("Dikkat",             "Attention") }
    static var critical:     String { L("Kritik",             "Critical") }
    static var fallbackRestart: String { L("Yeniden başlatma fallback", "Fallback restart") }
    static var inconclusive: String { L("Belirsiz", "Inconclusive") }
    static var deferred:     String { L("Ertelendi", "Deferred") }
    static var reason:       String { L("Sebep",              "Reason") }
    static var wait:         String { L("Bekleme",            "Wait") }
    static var verify:       String { L("Doğrulama",          "Verify") }
    static var lastOk:       String { L("son başarılı",       "last ok") }
    static var idle:         String { L("Hazır",              "Idle") }
    static var checking:     String { L("Kontrol",            "Checking") }
    static var updateAvailableShort: String { L("Güncelleme var", "Update available") }
    static var failed:       String { L("Hata",               "Failed") }
    static var automationWarningTitle: String { L("Otomasyon dikkat istiyor", "Automation needs attention") }
    static var automationCriticalTitle: String { L("Otomasyon acil dikkat istiyor", "Automation needs immediate attention") }
    // Settings bar
    static var dark:         String { L("Koyu",               "Dark") }
    static var light:        String { L("Açık",               "Light") }
    static var hideEmail:    String { L("Gizle",              "Hide") }
    static var showEmail:    String { L("Göster",             "Show") }
    static var langAuto:     String { L("Oto",                "Auto") }
    static var back:         String { L("Geri",              "Back") }
    static var limitReset:   String { L("Limit sıfırlandı", "Limit reset") }
    static var readyToUse:   String { L("kullanıma hazır", "is ready to use again") }
}
