# Zamanla

İş ve kişisel hayat için zaman yönetimi uygulaması. Android ve Windows'ta
aynı koddan çalışır; veriler Supabase üzerinden cihazlar arasında eşitlenir.
Yapay zeka sağlayıcıdan bağımsızdır: Claude, OpenAI, Gemini veya OpenAI uyumlu
herhangi bir sunucu (Ollama, LM Studio, OpenRouter, Groq…) uygulama içinden
seçilir.

## Özellikler

| Ekran | Ne yapar |
|---|---|
| **Bugün** | Gecikmiş ve bugünkü görevler, sıradaki takvim blokları, günlük odak süresi, alışkanlıklar, ilerleme halkası |
| **Görevler** | Tarihe göre gruplu liste, alt görevler, öncelik, tahmini süre, tekrar (günlük/hafta içi/haftalık/aylık), arama; **Eisenhower matrisi** (sürükle-bırak) |
| **Takvim** | Gün/hafta görünümü, zaman blokları, boş alana dokunarak ekleme, sürükleyerek taşıma ve (Windows'ta) boyutlandırma, planlanmamış görevler paneli |
| **Odak** | Pomodoro ve kronometre; süreler otomatik zaman kaydı olur; uygulama kapansa da kaldığı yerden devam eder; bitince bildirim |
| **Alışkanlıklar** | Haftanın belirli günleri, günlük hedef (ör. 8 bardak su), seri (🔥) takibi |
| **Hedefler** | Bağlı görevlerle ya da sayısal (12/24 kitap) ilerleme, hedef tarihi |
| **İstatistik** | Haftalık/aylık odak süresi, alanlara göre dağılım, iş/kişisel dengesi, en çok zaman alan görevler |
| **Asistan** | Verilerinin özetiyle sohbet: "Bugün neye odaklanmalıyım?", "Haftamı değerlendir" |

Her ekranda **Tümü / İş / Kişisel** (ve eklediğin diğer alanlar) filtresi vardır.

Yapay zeka özellikleri:
- **Hızlı ekle**: "Yarın 14:00 müşteriyle toplantı 1 saat, cuma rapor teslimi önemli" → takvim etkinliği + görev.
- **Günümü planla**: Açık görevleri çalışma saatlerindeki boşluklara yerleştiren zaman bloğu önerisi; onaylarsan takvime eklenir.
- **Görevi parçala**: Büyük bir görevi alt görevlere böler.
- **Asistan**: Görevlerin, takvimin, zaman kayıtların, alışkanlık ve hedeflerinle ilgili sorular.

Windows kısayolları: `Ctrl+N` yeni görev, `Ctrl+K` hızlı ekle, `Ctrl+1…9` ekranlar.

## Kurulum

Gerekenler: Flutter 3.47+ (stable). Windows sürümünü derlemek için bir Windows
bilgisayar ve Visual Studio 2022 ("Desktop development with C++" iş yükü)
gerekir; Mac'ten Windows derlenemez — bunun için aşağıdaki GitHub Actions
iş akışını kullanabilirsin.

```bash
flutter pub get
```

```bash
dart run build_runner build --delete-conflicting-outputs
```

### 1. Supabase (cihazlar arası eşitleme)

1. [supabase.com](https://supabase.com) üzerinde ücretsiz bir proje aç.
2. **SQL Editor**'de `supabase/schema.sql` dosyasının tamamını çalıştır.
   Tablolar, satır düzeyi güvenlik (her kullanıcı yalnızca kendi verisini
   görür), çakışma tetikleyicisi ve realtime yayını oluşturulur.
3. **Project Settings > API** sayfasından proje URL'sini ve *publishable*
   anahtarı (eski projelerde *anon* anahtarı) al.
4. `env.example.json` dosyasını `env.json` olarak kopyalayıp bu değerleri yaz.
   `env.json` git'e eklenmez.
5. İsteğe bağlı: **Authentication > Providers > Email** altında "Confirm email"
   kapatılırsa kayıt olduktan hemen sonra giriş yapılabilir.

`env.json` boş bırakılırsa uygulama yalnızca yerel modda çalışır (giriş ekranı
gösterilmez, veriler cihazda kalır).

### 2. Çalıştırma

```bash
flutter run --dart-define-from-file=env.json
```

VS Code'da `.vscode/launch.json` içindeki "Zamanla" yapılandırması bu
parametreyi zaten geçer.

### 3. Yayın derlemeleri

```bash
flutter build apk --release --dart-define-from-file=env.json
```

Windows bilgisayarda:

```bash
flutter build windows --release --dart-define-from-file=env.json
```

```bash
dart run msix:create --build-windows false
```

Kurulum dosyası `build/windows/x64/runner/Release/` altında oluşur. Play
Store'a yüklemeden önce `android/app/build.gradle.kts` içinde kendi imzalama
anahtarını ve `applicationId` değerini ayarla.

### GitHub Actions

`.github/workflows/build.yml` her `main` gönderiminde testleri çalıştırır,
Windows (exe + MSIX) ve Android (APK) derlemelerini yapıp **Artifacts** olarak
yükler. Supabase bilgilerini depo ayarlarında **Secrets** olarak tanımla:
`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`.

## Yapay zeka sağlayıcısı

Uygulamada **Ayarlar > Yapay zeka** bölümünden seçilir; "Bağlantıyı test et"
ile denenir. API anahtarı yalnızca cihazın güvenli deposunda (Android Keystore /
Windows Credential Manager) tutulur ve senkronize edilmez.

| Sağlayıcı | Varsayılan model | Not |
|---|---|---|
| Anthropic (Claude) | `claude-opus-5-5` | Yapılandırılmış JSON çıktı, reddetme durumunda sunucu taraflı yedek model |
| OpenAI | `gpt-5` | `json_schema` yanıt formatı |
| Google Gemini | `gemini-2.5-flash` | JSON yanıt modu |
| OpenAI uyumlu | — | Ollama, LM Studio, OpenRouter, Groq, DeepSeek…; adresi ve modeli sen girersin |

Yeni bir sağlayıcı eklemek için `lib/ai/providers.dart` içinde `AiClient`
arayüzünü uygulayan bir sınıf yazıp `AiProviderKind`'a eklemek yeterli;
özellikler (`lib/ai/ai_service.dart`) sağlayıcıdan bağımsızdır.

> Uygulamayı başkalarına dağıtacaksan, kullanıcılardan anahtar istemek yerine
> isteği bir Supabase Edge Function üzerinden geçirip anahtarı sunucuda tutmak
> daha güvenlidir.

## Mimari

```
lib/
  ai/            Sağlayıcıdan bağımsız AI katmanı (istemciler + özellikler)
  core/          Ortam, tema, tarih yardımcıları, ayarlar, bildirimler
  data/          drift (SQLite) şeması, depolar, Supabase senkronizasyonu
  features/      Ekranlar (today, tasks, calendar, focus, habits, goals, stats, ai, settings, auth)
  widgets/       Ortak bileşenler
  providers.dart Riverpod sağlayıcıları
supabase/schema.sql
```

- **Çevrimdışı öncelikli**: Arayüz her zaman yerel SQLite veritabanından okur;
  internet olmadan tam çalışır.
- **Senkronizasyon**: Değişen satırlar `dirty` olarak işaretlenir ve gönderilir;
  diğer cihazların değişiklikleri sunucu zaman damgasına göre çekilir. Çakışmada
  son düzenleme kazanır; düzenleme zaman damgası her zaman bir önceki sürümden
  yenidir, böylece saati geride olan cihazların düzenlemeleri kaybolmaz. Supabase
  realtime sayesinde diğer cihazdaki değişiklik birkaç saniyede gelir.
- Silmeler yumuşaktır (`deleted`), böylece diğer cihazlara da yayılır.

## Testler

```bash
flutter test
```

AI yanıt ayrıştırma ve sağlayıcı istek formatları, iki cihazlı senkronizasyon
senaryoları (çakışma, saat farkı, silme, gönderim sırasında düzenleme,
sayfalama), tekrar eden görevler, alışkanlık serileri ve takvim yerleşimi
test edilir.
