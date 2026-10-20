# Total Command 0.2.2

<img src="Resources/AppIcon.png" width="96" alt="Total Command ikonu">

macOS için Swift/AppKit ile geliştirilmiş, Total Commander’ın çift panel çalışma biçiminden esinlenen bağımsız dosya yöneticisi.

## Açma ve derleme

[İmzalı ve Apple noter onaylı DMG’yi indirin](https://github.com/ferdisahin/total-command/releases/tag/v0.2.2), açın ve `TotalCommand.app` dosyasını Uygulamalar klasörüne sürükleyin. Intel/Apple Silicon ve macOS 13+ içindir. 0.2.2 erken önizleme sürümüdür.

Homebrew ile kurulum:

```sh
brew install --cask ferdisahin/tap/total-command
```

Güncellemek için `brew update` ardından `brew upgrade --cask ferdisahin/tap/total-command` kullanın. Kaynaktan yapılan varsayılan geliştirme derlemeleri ad-hoc imzalıdır.

Kaynaklardan derlemek için Xcode komut satırı araçlarıyla `./build.sh`, testler için `./test.sh` çalıştırın. Harici paket kurulumu gerekmez. Arşiv işlemleri macOS’un `/usr/bin/bsdtar` aracını kullanır.

## Güncelleme kontrolü

Menüden **Total Command → Güncellemeleri Kontrol Et…** veya **Ayarlar → Güncellemeler** üzerinden yeni sürüm kontrolü yapılabilir. İsteğe bağlı günlük/haftalık kontrol ve önizleme kanalı vardır. Otomatik kontrol varsayılan olarak kapalıdır. Yeni sürüm bulunduğunda GitHub indirme sayfası açılır; uygulama kendini otomatik olarak değiştirmez. Ayrıntılar: [güncelleme davranışı](docs/UPDATES.md).

## Dosya yönetimi

- İki bağımsız panel, panel başına sekmeler, liste/simge görünümü.
- Doğrudan klasör yolu, geri/ileri/üst klasör, diskler ve sık kullanılan konumlar.
- Tıklanabilir sütun başlıklarıyla ad, uzantı, boyut ve tarih sıralaması.
- Canlı dosya adı filtresi, gizli dosyalar, çoklu seçim, desenle seçim ve seçimi tersine çevirme.
- Arka planda kopyalama ve taşıma, öğe sayısına göre ilerleme ve iptal.
- Finder’dan veya diğer panelden sürükleyip bırakma. Bırakma, açık hedef klasöre kopyalar.
- Command+C/X/V ile dosya panosu; metin alanlarında standart metin düzenleme davranışı.
- Yeni klasör/metin dosyası, tekli ve önizlemeli toplu yeniden adlandırma.
- Quick Look, seçilen metin düzenleyicisiyle açma, dosya bilgisi, Finder’da gösterme, yol kopyalama.
- Simge görünümünde desteklenen görsel/PDF/video dosyaları için Quick Look küçük resimleri.
- Sağ tık menüleri ve kalıcı favoriler.
- Boyut/tarih temelli panel karşılaştırması ve önizlemeli tek yönlü klasör eşitleme.
- Etkin klasörde komut çalıştırma ve ayrı çıktı penceresi; Terminal’de açma.
- Finder üzerinden SMB/AFP sunucusuna bağlanma; Yenile ile yeni bağlanan diski listeye ekleme.

## Arşivler

ZIP ve 7z oluşturma; sistem arşiv motorunun desteklediği ZIP, 7z, RAR, TAR, GZ, BZ2 ve XZ dosyalarını çıkarma. RAR varyantları sistem motorunun kabiliyetleriyle sınırlıdır; şifreli arşivler desteklenmez.

Arşive çift tıklamak içeriğini geçici bir klasörde açar. Buradaki değişiklikler özgün arşive geri yazılmaz. Arşiv kökünde Üst Klasör ile kaynak konumuna dönülür. Çıkar komutu karşı panelde yeni, benzersiz klasör oluşturur. Geçici arşiv klasörleri uygulamadan çıkıldığında temizlenir.

## Ayrıntılı ayarlar

Üstteki **Ayarlar** düğmesi veya **Total Command → Ayarlar…** / Command+,:

| Bölüm | Seçenekler |
|---|---|
| Genel | Sekmeleri geri yükleme, başlangıç klasörleri, metin düzenleyicisi, varsayılan görünüm |
| Görünüm | Sistem/açık/koyu tema, 11–15 pt yazı, üç satır aralığı, tarih biçimi, klasör önceliği, uzantı sütunu, küçük resimler, gizli dosyalar, komut satırı |
| Dosyalar | Çakışmada sor/ikisini koru/atla; taşıma ve Çöp Kutusu onayları |
| Arşivler | Varsayılan ZIP/7z biçimi, çift tıklayınca panelde gezinme |
| Arama | Gizli dosyaları dahil etme, 100/1.000/5.000 sonuç sınırı |
| Klavye | F tuşlarını etkinleştirme, Boşluk önizlemesi, F3–F8 işlemlerini ayrı ayrı atama |

Ayarlar otomatik kaydedilir. Varsayılanlara dönüş, favorileri ve kayıtlı sekmeleri silmez. Başlangıç klasörleri sonraki açılışta kullanılır; sekme geri yükleme açıksa son sekmeler önceliklidir. Görünüm ayarlarının uygulanması iki paneli günceller.

## Varsayılan kısayollar

F2 yeniden adlandırır; F3 önizler; F4 düzenleyicide açar; F5 kopyalar; F6 taşır; F7 klasör oluşturur; F8 Çöp Kutusu’na taşır. Mac klavyesinde Fn gerekebilir. Boşluk Quick Look; Tab panel değiştirir; Return açar; Command+Yukarı üst klasöre çıkar. Command+T/W sekme açar/kapatır; Command+D/B favori ekler/açar; Command+F arar; Command+M toplu adlandırır; Command+R yeniler; Command+U panelleri değiştirir.

## İşlem davranışları ve sınırlar

Aynı adlı dosyalarda varsayılan davranış sormak ve iki kopyayı da korumaktır. Hedefteki dosya otomatik ezilmez. Eşitleme kaynak panelden hedefe tek yönlüdür, boyut/tarihe bakar; hedefteki fazlalıkları silmez. Güncellenen hedeflerin önceki halleri `.totalcommand-backup` ekli dosyalarda tutulur. İçerik/hash karşılaştırması yapılmaz.

Aynı anda tek arka plan işi çalışır. İptal, kopyalama/taşımada dosyalar arasında kontrol edilir; büyük tek bir dosyanın bitmesini bekleyebilir. İptal edilmiş bir klasör kopyasının geçici hedefi temizlenir; önceki tamamlanmış dosyalar korunur. İşlem günlüğü veya tüm işlemi geri alma yoktur. Arama dosya adlarına bakar, içerik aramaz ve uygulama paketlerini taramaz.

Bu sürüm Total Commander ile tam özellik eşitliğine sahip değildir. Yerleşik FTP/SFTP, eklenti sistemi, şifreli/parçalı arşiv yönetimi, arşive geri yazma, dosya bölme/birleştirme, iki yönlü senkronizasyon, işlem kuyruğu ve gelişmiş içerik karşılaştırması henüz yoktur.

## Doğrulama

`test.sh`: Türkçe/boşluklu adlarda kopyalama, ad çakışması, iç içe klasörler, sembolik bağlantı, kendi içine kopyalama engeli, iptal ve geçici dosya temizliği, taşıma, toplu adlandırma, hedef çakışması, arşiv yolları, yedekli eşitleme, ayar varsayılanları/kalıcılık/sıfırlama, ZIP ve 7z oluşturup çıkarma testleri.

Arayüzde çift panel, liste/simge görünümü, sekme açma/kapatma, kopyalama, toplu adlandırma önizlemesi ve uygulama, Ayarlar bölümleri ve bir ayar değişikliği kontrol edildi. Tüm arşiv varyantları ve uzak sunucularla uçtan uca test yapılmadı.

## Lisans ve dağıtım

Copyright © 2026 Ferdi Sahin. **GPL-3.0-only**; tam metin [LICENSE](LICENSE). Dağıtılan değiştirilmiş sürümlerin ilgili kaynakları da GPLv3 koşullarıyla sunulmalıdır. Yazılım garanti verilmeden sağlanır.

GitHub hedefi: [ferdisahin/total-command](https://github.com/ferdisahin/total-command). Açık kaynak depo ve Developer ID ile imzalanıp Apple noter onayı alınmış 0.2.2 önizleme sürümü yayınlandı. Homebrew dağıtımı [kişisel tap](https://github.com/ferdisahin/homebrew-tap) üzerinden yapılır; merkezi Homebrew Cask kataloğuna kabul edildiği anlamına gelmez. İmzalama, noter onayı ve kişisel Homebrew tap kurulumu için [dağıtım rehberi](docs/DISTRIBUTION.md).
