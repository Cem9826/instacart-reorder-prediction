# Instacart — Tekrar Alım Tahmini

Bir müşterinin bir sonraki siparişinde, daha önce aldığı ürünlerden hangilerini tekrar alacağını tahmin eden bir model. Ayrıca bu tahminin bir öneri sistemi için ne kadar kullanışlı olduğunu ölçen bir etki analizi.

Akış: BigQuery (SQL) → Python (VS Code) → Looker Studio

---

## Ana soru

Öneri ekranında sınırlı sayıda slot var. Kullanıcının geçmişte aldığı 60 küsur ürün arasından hangilerini göstermeli?

İkinci soru ilkinden ayrı: bu tahmin gerçekten işe yarar mı? Model doğru tahmin etse bile, kullanıcı o ürünü zaten alacaksa öneri bir şey değiştirmez.

---

## Veri

Instacart Online Grocery Basket Analysis veri seti. Altı tablo, 3,4 milyon sipariş, 32,4 milyon ürün satırı.

| Tablo | Satır |
|---|---|
| orders | 3.421.083 |
| order_products_prior | 32.434.489 |
| order_products_train | 1.384.617 |
| products | 49.688 |
| aisles | 134 |
| departments | 21 |

`eval_set` kolonu siparişleri üçe ayırıyor: prior (geçmiş), train (hedef), test. Test siparişlerinin içeriği yayınlanmamış — Kaggle yarışması için gizlenmiş. Bu yüzden yalnızca 131.209 train kullanıcısıyla çalışıldı.

---

## Kapsam beyanı

Bu bölüm sonuçlardan önce geliyor, çünkü sonuçların nasıl okunacağını belirliyor.

**Sipariş aralığı 30 günde kırpılmış.** `days_since_prior_order` kolonunun maksimum değeri 30. 29'da 16.976 sipariş varken 30'da 306.137 var — 18 katına çıkıyor. Bu doğal bir dağılımın kuyruğu değil; Instacart 30 günü aşan tüm aralıkları 30'a yazmış. 35 gün sonra dönen müşteri ile 6 ay sonra dönen aynı görünüyor. **Churn tanımı bu veriyle kurulamaz.**

**Aday seti sınırı.** Model yalnızca kullanıcının daha önce aldığı ürünleri değerlendiriyor. Train siparişlerindeki ürünlerin %40,1'i kullanıcının hiç almadığı ürünler ve model bunları asla yakalayamaz. Ulaşılabilir maksimum F1 = **0,6986** (kullanıcı bazında hesaplandı).

**Veride olmayanlar:** adet bilgisi yok (1 süt mü 6 süt mü belli değil), fiyat ve marj yok, takvim tarihi yok (mevsimsellik ölçülemez), `order_dow` gün kodlaması açıklanmamış (0 pazar mı pazartesi mi bilinmiyor), öneri kaydı yok (kime ne gösterildiği kayıtlı değil).

**Filtreler:** `order_number` 100'de kırpılmış. Kullanıcı başına minimum 4 sipariş var; özellik tablolarında bu prior'a bakıldığı için minimum 3'e düşüyor.

**Tekrar alım oranı sadakati değil, tüketim hızını ölçüyor.** Ölçüldü: ürün bazında tekrar alım oranı ile gerçek alım aralığı arasındaki korelasyon **r = -0,81** (n = 8.290 ürün). En düşük tekrar oranlı dilimde ortalama alım aralığı 56 gün, en yüksekte 21,4 gün. Kekik yılda birkaç kez alınıyor; bu kullanıcının memnuniyetsizliği değil, kavanozun bitmemesi.

**`u_days_since_last_order` istisnası.** Bu tek özellik train siparişinden geliyor. Sızıntı değil: kullanıcı sipariş verdiği anda son siparişinden kaç gün geçtiği zaten bilinen bir bilgi.

---

## Yöntem

### Faz 1 — BigQuery

Üç ayrı dataset: `instacart_raw` (ham, değiştirilmez), `instacart_clean` (görünümler), `instacart_features` (özellik tabloları).

**Veri kalitesi denetimi.** 15'in üzerinde kontrol çalıştırıldı: boş değerler, aralık dışı değerler, sipariş içi ürün tekrarı, yetim kayıtlar, çift ürün adları. Temizlik gerektiren bir sorun çıkmadı. 30 gün kırpması bu adımda tespit edildi.

**Keşif analizi.** Altı sorgu grubu: zaman kalıpları, sipariş sırası, sepet yapısı, ürün ve kategori, kullanıcı repertuarı, sipariş ritmi.

**Özellik tabloları.** Dört tablo, tamamı yalnızca prior siparişlerden:

| Tablo | Satır | İçerik |
|---|---|---|
| user_features | 131.209 | hacim, sepet, ritim, davranış |
| product_features | 49.677 | hacim, sadakat, konum, ritim, normalize lift |
| aisle_features / department_features | 134 / 21 | aynı metrikler kategori düzeyinde |
| user_product_features | 8.474.661 | sayım, zamanlama, oran, son-5, konum, kişisel ritim |

**Eğitim seti:** 8.474.661 satır, 131.209 kullanıcı, pozitif oran %9,78.

**Sızıntı kontrolleri.** Dört kontrol: kaynak denetimi (her özellik sorgusunun train tablosuna dokunup dokunmadığı), filtre denetimi, korelasyon taraması (en yüksek 0,386 — eşiğin çok altında), deneysel test (aşağıda).

### Faz 2 — Python

**Bölme.** Kullanıcı bazında üçe: train %70 / validation %15 / test %15. Satır bazında bölünseydi aynı kullanıcının bazı ürünleri train'de bazıları validation'da olurdu ve model kullanıcıyı ezberleyip yalancı yüksek skor verirdi. Üç set arasında kullanıcı çakışması sıfır.

Üç set kullanılmasının sebebi: eşik ve kalibrasyon validation'da ayarlandı, test yalnızca son raporlama için bir kez açıldı.

**Baseline'lar.** Model kurmadan önce beş basit kural ölçüldü. Modelin bu tabloyu ne kadar geçtiği, performansın tek dürüst göstergesi.

**Modeller.** Önce lojistik regresyon (yorumlanabilirlik için), sonra LightGBM (performans için).

---

## Sonuçlar

### Model performansı

Tüm değerler validation setinde, kullanıcı bazlı F1:

| Yöntem | F1 | Precision | Recall | AUC | Tavanın %'si |
|---|---|---|---|---|---|
| LightGBM (kullanıcı bazlı eşik) | 0,3771 | 0,3542 | 0,4600 | 0,8378 | %54,0 |
| LightGBM (sabit eşik 0,18) | 0,3712 | 0,3346 | 0,5082 | 0,8378 | %53,1 |
| Lojistik regresyon | 0,3594 | 0,3029 | 0,5478 | 0,8267 | %51,5 |
| Baseline 4: alım oranı ≥ 0,35 | 0,3178 | 0,2408 | 0,6153 | — | %45,5 |
| Baseline 2: son siparişi tekrarla | 0,3123 | 0,2873 | 0,4283 | — | %44,7 |
| Baseline 3: en sık alınan 10 ürün | 0,3068 | 0,2754 | 0,4844 | — | %43,9 |
| Baseline 1: tüm adayları öner | 0,2153 | 0,1318 | 0,9344 | — | %30,8 |
| Baseline 0: hiçbir şey önerme | 0,0000 | 0,0000 | 0,0000 | — | %0 |

**Test setinde nihai sonuç: F1 = 0,3777.** Validation ile farkı 0,0006 — model aşırı öğrenmemiş, eşik seçimi validation'a özel bir tesadüfe dayanmıyor.

Pratik karşılığı: model kullanıcı başına ortalama 8 ürün öneriyor, 3'ü tutuyor.

Basit kuralların üzerine kazanç 0,0599. Bunun yaklaşık %70'ini lojistik regresyon tek başına sağlıyor; LightGBM'in eklediği 0,0177.

### Bulgular

**1. Zamanlama, hacimden güçlü bir sinyal.** "Son siparişi tekrarla" kuralı (0,3123), "en sık aldığı 10 ürünü öner" kuralını (0,3068) geçiyor. Lojistik regresyonun en güçlü iki katsayısı da zamanlama: `up_days_since_last` (-0,499) ve `up_orders_since_last` (-0,389). Özellik öneminde ilk beş sıranın tamamı kullanıcı-ürün özellikleri, toplam gain'in %78,7'si.

**2. Kullanıcı ne kadar aldığını değil, ne aldığını değiştiriyor.** Sipariş sayısı arttıkça tekrar alım oranı %0'dan %82'ye çıkıyor, ama ortalama sepet boyutu 10 civarında sabit kalıyor.

**3. Repertuar doymuyor.** İlk siparişte ortalama 7,3 koridor, 10.'da 26,4, 30.'da 39,2, 99.'da 52,4. Artış hızı sürekli düşüyor ama sıfırlanmıyor. İlk beş siparişte 12 koridor eklenirken, 50-99 arasındaki elli siparişte yalnızca 7 ekleniyor. Hayatta kalma yanlılığı kontrol edildi: en az 20 siparişi olan kullanıcılarla çizilen eğri genel eğriden ayrılmıyor (10. siparişte fark 0,17 koridor).

**4. Düzenlilik tekrar alımı artırıyor, ama sipariş sayısı çok daha güçlü.** Sipariş aralığı ve sipariş sayısı sabitlendiğinde, düzenli kullanıcıların tekrar oranı 12 kombinasyonun 12'sinde de dağınık kullanıcılardan yüksek (4,6 ile 11,3 puan arası). Buna karşılık sipariş sayısı etkisi 39 puan. Ham bantlarda bu iki etki birbirine karışıyordu.

**5. Model her tahminde emin değil, belirsizlik yapısal.** Tüm tahminlerin yalnızca %3'ü 0,50'nin üzerinde. Kullanıcının geçmişte aldığı her ürün aday sayılıyor, ama bir sonraki siparişte ortalama 6,3 tanesi alınıyor.

### Kalibrasyon

Model 0,30 dediğinde gerçekten %30 civarı alınıyor mu? Yirmi kutuda ölçüldü, **ortalama mutlak hata 0,0007**. Yirmi kutunun tamamında sapma 0,0041'in altında.

İsotonic regresyon uygulanmadı — koşul gerçekleşmedi. Kalibrasyonun bu kadar iyi olması üç tasarım kararının sonucu: `objective='binary'`, sınıf ağırlığı kullanılmaması ve erken durdurmanın `binary_logloss` üzerinden yapılması.

### Sızıntı kontrolü (Kontrol 4)

En güçlü özellikler çıkarılıp model sıfırdan yeniden eğitildi:

| Model | F1 | Tur | Kayıp |
|---|---|---|---|
| Tam model | 0,3712 | 553 | — |
| `up_days_since_last` çıkarıldı | 0,3699 | 682 | 0,0014 |
| `up_last5_purchases` çıkarıldı | 0,3709 | 607 | 0,0004 |

Kayıplar sıfıra yakın. Bu sızıntı işareti değil — zamanlama bilgisi birden çok kolonda mevcut ve hepsi yalnızca prior'dan hesaplanmış. Sızıntı olsaydı mutlak skor tavana dayanırdı; 0,3712 tavanın %53'ü.

Permutation importance ile gain sıralaması karşılaştırıldı ve iki liste farklı çıktı. `up_last5_purchases` gain'de birinci (%33,5) ama permutation'da dördüncü; `up_days_since_last` gain'de beşinci ama permutation'da birinci. Sebep fazlalık: yedeği olan özellikler karıştırıldığında model diğer kolonlara dönüyor.

---

## Etki analizi

Model doğru tahmin ediyor. Peki bu tahminden aksiyon çıkıyor mu?

### Olasılık bantları

Tahminler üçe ayrıldı (sınırlar 0,10 ve 0,50):

| Bant | Satır payı | Alımların payı | Gerçek alım oranı |
|---|---|---|---|
| Bariz (≥ 0,50) | %3,0 | %19,7 | 0,643 |
| Artımsal (0,10–0,50) | %25,1 | %54,8 | 0,215 |
| Düşük (< 0,10) | %71,9 | %25,5 | 0,035 |

Beklenti, doğru tahminlerin çoğunun bariz bantta toplanmasıydı. Tersi çıktı: alımların yalnızca %19,7'si bariz bantta, %54,8'i modelin kararsız olduğu bölgede.

Sınır seçimine duyarlılık kontrol edildi. Bariz bandın payı dört farklı sınır setinde %12,6 ile %28,5 arasında değişiyor, hiçbirinde çoğunluğa yaklaşmıyor.

Artımsal bant kendi içinde ayrıştırılabiliyor: bant içi AUC 0,6643, en üst dilim ile en alt dilim arasında 4,12 kat fark. Üst 3 dilim kullanıcı başına 4,8 çift ve tüm alımların %26,8'i — beş slotluk bir öneri kotasına oturuyor.

### Eşleştirme analizi

Soru: bir ürünün son siparişte sepette olması, bir sonraki siparişte alınmasına sebep mi oluyor?

Ham fark 0,2188. Ama iki grup baştan çok farklı: son siparişte olan ürünler kullanıcının siparişlerinin %77'sinde alınan ürünler, olmayanlar %21.

Eğilim skoru eşleştirmesi yapıldı. Ortak destek sorunu ortaya çıktı — eğilim skoru modelinin AUC'si 0,9681, yani müdahale neredeyse tamamen eşleştirme değişkenleri tarafından belirleniyor. Çakışma bölgesine ([0,10 – 0,90]) daraltıldı.

Eşleştirme kalitesi kontrol edildi: sekiz değişkenin sekizi de |SMD| < 0,10 eşiğinin altına indi. `up_order_rate` 2,3695'ten -0,0161'e düştü.

| | Değer |
|---|---|
| Eşleştirilmiş müdahale grubu | %37,7 |
| Eşleştirilmiş kontrol grubu | %26,3 |
| ATT | 0,1133 [%95 GA: 0,1089 – 0,1178] |
| Ham fark | 0,2188 |
| Karışma payı | 0,1055 (%48,2) |

Ham farkın neredeyse yarısı karışmaymış.

### Placebo testi

Bu 0,1133 nedensel olarak yorumlanabilir mi?

Rastgele atanmış sahte müdahale yerine zamansal negatif kontrol kullanıldı: **ürün sondan bir önceki prior siparişte var mıydı?** Müdahale geçmişi etkileyemez, dolayısıyla eşleştirme düzgünse buradaki farkın sıfıra yakın çıkması gerekir.

| | Değer |
|---|---|
| Placebo etkisi | **-0,1570** |
| Gerçek etki (ATT) | 0,1133 |
| Oran | %139 |

**Test başarısız.** Placebo etkisi gerçek etkiden büyük ve ters yönde. Eşleştirilen gruplar müdahaleden önceki dönemde bile farklıydı.

Ritim değişkenleri (`up_avg_repeat_gap`, `up_days_since_last`, `u_avg_gap`, `u_sd_gap`) eklenerek ikinci kez denendi. Durum kötüleşti: eğilim skoru AUC'si 0,9980'e çıktı, dengeleme 8/8'den 9/12'ye düştü, placebo etkisi -0,5533 oldu.

### Duyarlılık analizi

Gizli bir faktörün etkiyi tamamen silmesi için müdahale görme şansını **1,8 kat** değiştirmesi yeterli. Gözlemsel çalışmalarda 4-5 civarı "sağlam" sayılır; 1,8 kırılgan.

Zaten varsayımsal bir faktör aramaya gerek yok — placebo testi böyle bir faktörün fiilen var olduğunu gösterdi.

### Sonuç

**0,1133 nedensel bir etki olarak raporlanamaz.** Bir ürünün son siparişte olması ile tekrar alınması arasındaki ilişki güçlü, ancak bu ilişkinin ne kadarının "sepette görmenin etkisi", ne kadarının ürünün tüketim ritminden geldiği bu veriyle ayrılamıyor.

Bu bir başarısızlık değil, analizin kendi kendini denetleyen kısmının çalışmasıdır. Placebo testi yapılmasaydı 0,1133 "son siparişte olmanın etkisi" diye raporlanacak ve yanlış olacaktı.

---

## Veriden çıkan ve çıkmayan

**Çıkanlar:** Model görülmemiş kullanıcılarda F1 = 0,3777 veriyor. Olasılıklar kalibre. Alımların %54,8'i artımsal bantta. Artımsal bandın üst 3 dilimi kullanıcı başına 4,8 çift ve tüm alımların %26,8'i.

**Çıkmayanlar:** Önerinin etkisi (veride öneri kaydı yok). 0,1133'ün nedensel yorumu. Hangi bandın aksiyon alanı olduğu. Churn.

**Ölçmek için gereken:** Rastgele atamalı bir A/B testi. Öneriler artımsal bandın üst dilimlerine verilmeli, bariz bant kontrol olarak tutulmalı. Artımsal bantta temel oran %21,5; 3 puanlık bir farkı %80 güçle yakalamak için grup başına yaklaşık 3.500 kullanıcı gerekir.

---

## Repo yapısı

```
├── sql/                    her adım için ayrı .sql dosyası
├── notebook/
│   └── instaract.ipynb     keşif, model, etki analizi
├── src/
│   ├── data_loader.py      parquet okuma, bellek optimizasyonu
│   ├── splitter.py         kullanıcı bazlı üçlü bölme
│   └── metrics.py          kullanıcı bazlı F1, precision, recall
├── outputs/
│   ├── figures/            11 grafik
│   ├── tables/             6 özet CSV
│   └── models/             eğitilmiş LightGBM
└── README.md
```

---

## Çalıştırma

Gereken kütüphaneler: `pandas`, `numpy`, `google-cloud-bigquery`, `db-dtypes`, `lightgbm`, `scikit-learn`, `matplotlib`, `seaborn`, `pyarrow`.

1. `sql/` altındaki dosyaları sırayla BigQuery'de çalıştır. Üç dataset ve özellik tabloları oluşur.
2. Notebook'taki indirme hücresi eğitim setini parquet olarak diske yazar (~130 dk, 884 MB). Dosya varsa hücre atlanır.
3. Notebook'u baştan sona çalıştır.

Not: Cloud Storage Sandbox modunda kullanılamadığı için dışa aktarım BigQuery'den Arrow akışıyla doğrudan parquet'e yazılarak yapıldı.

---

## Teknik notlar

**Bellek.** 8,47 milyon satır × 53 kolon, 8 GB RAM'li bir makinede. Tip optimizasyonu (int64 → int8/int16/int32, float64 → float32) bellek kullanımını 3,6 GB'dan 1,3 GB'a düşürdü.

**Determinizm.** NTILE fonksiyonlarına ikinci sıralama kriteri olarak `product_id` eklendi; eşit satışlı ürünler her çalıştırmada aynı dilime düşüyor. Düzeltme öncesi iki çalıştırma arasında 1.198 ürünün dilimi değişiyordu.

**Döngüsel saat.** `u_avg_hour` yerine `u_hour_sin` ve `u_hour_cos` kullanıldı. Saat 23 ile saat 1'in aritmetik ortalaması 12 çıkıyordu.

**Ürün alım aralığı.** `p_avg_repeat_gap` ilk versiyonda `days_since_prior_order` ortalaması olarak hesaplanmıştı; bu ürünün alım aralığını değil kullanıcının sipariş aralığını ölçüyordu. Düzeltildi: her (kullanıcı, ürün) çiftinde ilk ve son alım arası gün sayısı, alım sayısı eksi bire bölünüyor. Baking Powder eski 7,6 → yeni 83,1 gün; Banana 10,5 → 18,6. Eski ve yeni değerler arasındaki korelasyon 0,20.
