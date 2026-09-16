# Instacart — İş Özeti

## Ne sorduk

Bir market sitesinin öneri ekranında sınırlı sayıda yer var. Müşterinin geçmişte aldığı 60 küsur ürün arasından hangilerini göstermeli?

Bunun arkasında ikinci bir soru var: bu öneri gerçekten işe yarıyor mu? Müşteri o ürünü zaten alacaksa, göstermenin bir faydası yok.

---

## Ne bulduk

**Model kullanıcı başına 8 ürün öneriyor, 3'ü tutuyor.** Hiç uğraşmadan "geçen sepeti aynen tekrarla" deseydik 10 öneriden 3'ü tutardı. Model bunun biraz üstünde ama mucize değil.

Mükemmele ulaşamamasının bir sebebi var: müşterilerin aldığı ürünlerin %40'ı daha önce hiç almadıkları ürünler. Model bunları göremiyor, çünkü sadece geçmişte alınanlar arasından seçim yapıyor.

**En işe yarayan bilgi zamanlama.** Müşterinin bir ürünü toplamda kaç kez aldığından çok, en son ne zaman aldığı ve ne sıklıkla aldığı önemli. İki müşteri aynı ürünü aynı sayıda almış olabilir; bir sonraki siparişte alıp almayacağını ayıran şey son alımın üzerinden geçen süre.

**"Sık tekrar alınan ürün" sadık müşteri anlamına gelmiyor.** Süt iki haftada bir alınıyor, kekik üç ayda bir. Bu fark beğeni değil, tüketim hızı. Kekik kavanozu bitmediği için alınmıyor. Bunu ölçtük: tekrar alım oranı düşük ürünlerin alım aralığı belirgin şekilde uzun.

**Müşteriler yeni şeyler denemeyi hiç bırakmıyor.** İlk siparişte ortalama 7 farklı reyondan alışveriş yapılıyor, 30. siparişte 39. Artış yavaşlıyor ama duruyor demek yanlış olur.

---

## Ne yapılmalı

Model kime ne önereceğini sıralayabiliyor. Ama hangi öneri gerçekten fark yaratır, onu söyleyemiyor.

Tahminleri üçe ayırdık:

- **Zaten alacakları.** Model çok emin. Bunlara öneri harcamak yer israfı. Toplam alımların %20'si.
- **Belirsiz olanlar.** Model kararsız. Bir hatırlatmanın fark yaratabileceği tek yer burası. Alımların %55'i.
- **Almayacakları.** Model eminlikle hayır diyor. Öneri boşa gider.

Şaşırtıcı olan şu: alımların çoğu belirsiz bölgede. Yani fırsat alanı sanılandan büyük.

Ama burada dikkatli olmak gerekiyor.

---

## Neyi bilemiyoruz

**Önerinin etkisini ölçemedik.** Veride öneri diye bir kayıt yok. Kime ne gösterildiği, tıklanıp tıklanmadığı belli değil. "Bu bölgeye öneri koyarsak satış şu kadar artar" diyemiyoruz.

Bunu test etmeye çalıştık. Bir ürünün geçen sepette olmasının, bu sepette alınmasına sebep olup olmadığını ölçmeye çalıştık. Benzer alışkanlıklara sahip müşterileri eşleştirip karşılaştırdık.

Sonuç umut vericiydi. Ama yöntemin kendisini test eden bir kontrol daha yaptık ve **o kontrol başarısız oldu**. Yani bulduğumuz sayı güvenilir değil.

Bunu gizlemek yerine yazıyoruz, çünkü kontrol yapılmasaydı yanlış bir sonuç raporlanacaktı.

**Müşteri kaybını da ölçemiyoruz.** Veride sipariş aralıkları 30 günde kesilmiş. 35 gün sonra dönen müşteri ile 6 ay sonra dönen aynı görünüyor.

---

## Sırada ne var

Öneri etkisi ancak deneyle ölçülür. Basit bir kurgu:

Müşteriler rastgele iki gruba ayrılır. Bir gruba belirsiz bölgeden öneri gösterilir, diğerine gösterilmez. Birkaç hafta sonra iki grubun satın alımları karşılaştırılır.

Grup başına 3.500 müşteri yeterli. Bu deney olmadan önerinin değeri hakkında kesin bir şey söylenemez.
