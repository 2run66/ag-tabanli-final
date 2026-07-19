# PROJE 5: İleri Seviye Veri Temizleme ve ETL Süreçleri Raporu

Bu projede kurumsal ortamlarda sıkça rastlanan oldukça "kirli" bir veri seti PostgreSQL özellikleri kullanılarak Yıldız Şema'ya (Star Schema) dönüştürülmüştür.

## Uygulanan Transformation (Dönüşüm) Teknikleri

1. **Deduplication (Tekilleştirme):** 
   `ROW_NUMBER() OVER (PARTITION BY ...)` Window Function yapısı kullanılarak veritabanına iki kere yüklenmiş kopya veriler tespit edilmiş ve sadece tek bir satır işleme alınmıştır.
   
2. **JSON ve RegEx (Düzenli İfadeler):** 
   Farklı sistemlerden gelen verilerin bir kısmı JSON objesi, bir kısmı ise düz metin olarak tutulmuştu. JSON olan veriler PostgreSQL'in `::jsonb ->> 'anahtar'` sözdizimi ile kolayca ayrıştırıldı. Düz metin (Text) olan verilerden iletişim bilgilerini çıkarmak için Regular Expressions kullanıldı (`[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+` ile email çıkarma vb.).

3. **Data Imputation ve Temizleme:**
   `$200` gibi döviz kurlu veriler RegEx ile rakamlardan arındırılıp (Dolar simgesi kaldırılarak) kurla çarpıldı. Eksik veri (`NULL` kelimesi) içeren tutarlar `0` olarak standartlaştırıldı. Farklı formatlardaki tarihler `CASE WHEN` bloğuyla ISO formatına çevrildi.

4. **Star Schema (Yıldız Şema) Modellemesi:**
   Ham veri tek bir devasa tabloda (`satislar_ham`) tutuluyordu. Bu veri anlamlı parçalara ayrılarak Data Warehouse mimarisinin temeli olan Boyut (`dim_musteri`, `dim_urun`) ve Gerçek (`fact_satis`) tablolarına Primary Key / Foreign Key yapısıyla dağıtıldı (Load aşaması).
