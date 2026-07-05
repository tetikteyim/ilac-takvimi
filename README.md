# İlaç Takvimi — Android Uygulaması

Basit ilaç kullanım takvimi:

- **Yatay ekranda** çalışır, açılışta **Günün Çizelgesi** gelir.
- Sağa kaydırınca **Kayıtlı İlaçlar**, bir daha kaydırınca **Yeni İlaç Ekle** sayfası.
- İlaç saatinde **telefon bildirimi** gelir (uygulama kapalıyken bile — Android'in alarm sistemi kullanılır).
- Dozları AÇ (sarı) / TOK (mavi) kutularıyla gösterir; aldığınız doza dokununca ✓ işaretlenir ve o dozun bildirimi iptal edilir.
- Veriler telefonda kalıcı olarak saklanır.

---

## APK'yı elde etmenin 2 yolu

### Yol A — GitHub ile (bilgisayara hiçbir şey kurmadan, ÖNERİLEN)

1. [github.com](https://github.com) adresinde ücretsiz bir hesap açın.
2. **New repository** deyip `ilac-takvimi` adında bir depo oluşturun (Private seçebilirsiniz).
3. Bu klasördeki **tüm dosyaları** (klasör yapısını bozmadan, `.github` klasörü dahil) depoya yükleyin.
   - Web arayüzünden: *Add file → Upload files* ile sürükleyip bırakın.
   - `.github/workflows/build.yml` dosyasının yüklendiğinden emin olun (gizli klasörler bazen atlanır; gerekirse *Add file → Create new file* ile adını `.github/workflows/build.yml` yazıp içeriğini yapıştırın).
4. Deponun **Actions** sekmesine gidin. "APK Derle" işi otomatik başlar (başlamadıysa *Run workflow* deyin). Derleme ~5-10 dakika sürer.
5. İş bitince yeşil ✓ olan çalıştırmaya tıklayın, en altta **Artifacts** bölümünden `ilac-takvimi-apk` dosyasını indirin (zip içinde `app-release.apk` çıkar).
6. APK'yı telefonunuza atın (WhatsApp/e-posta/kablo) ve dokunup kurun. Android "bilinmeyen kaynak" uyarısı verirse **İzin ver / Yine de yükle** deyin.

### Yol B — Bilgisayarınızda derleme

1. [Flutter SDK](https://docs.flutter.dev/get-started/install) ve Android Studio kurun.
2. Bu klasörde sırayla:

```bash
flutter create . --project-name ilac_takvimi --org com.ilactakvimi --platforms android
python3 patch_android.py
flutter pub get
flutter build apk --release
```

3. APK şurada oluşur: `build/app/outputs/flutter-apk/app-release.apk`
4. Telefonu USB ile bağlayıp doğrudan da kurabilirsiniz: `flutter install`

---

## İlk açılışta

- Uygulama **bildirim izni** ve **alarm/hatırlatıcı izni** ister — ikisine de izin verin, yoksa ilaç saati bildirimleri gelmez.
- Bazı telefonlarda (özellikle Xiaomi, Huawei, Oppo) pil tasarrufu bildirimleri geciktirebilir. Ayarlar → Pil → İlaç Takvimi → **Kısıtlama yok / Otomatik başlat** seçin.

## Dosya yapısı

```
ilac_takvimi/
├── lib/main.dart              # Uygulamanın tamamı
├── pubspec.yaml               # Bağımlılıklar
├── patch_android.py           # Android izin/ayar yaması
├── .github/workflows/build.yml # Otomatik APK derleme
└── README.md
```
