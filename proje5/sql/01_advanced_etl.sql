-- 01_advanced_etl.sql

-- 1. KIRLİ VERİ KAYNAĞI (Extract Aşaması İçin)
CREATE TABLE satislar_ham (
    id SERIAL PRIMARY KEY,
    musteri_tam_isim VARCHAR(150),
    iletisim_bilgisi TEXT, -- JSON formatında ama bozuk metin
    siparis_tarihi VARCHAR(50),
    satis_tutari TEXT, -- Rakam ve para birimi karışık
    urun_detay VARCHAR(200) -- İçinden kategori çekilecek
);

INSERT INTO satislar_ham (musteri_tam_isim, iletisim_bilgisi, siparis_tarihi, satis_tutari, urun_detay) VALUES 
('  ALİ yılmaz ', '{"email": "ali@mail.com", "telefon": "555-123-4567"}', '2023-10-12', '1250.50 TL', 'Elektronik - Laptop'),
('ayşe  Kaya ', '{"email": "ayse.kaya@mail", "telefon": "0532 999 88 77"}', '15/11/2023', '$200', 'Giyim - Kazak'),
('Mehmet DEMİR', '{"email": "mehmet@mail.com"}', '2023/12/01', 'NULL', 'Elektronik - Telefon'),
('  ALİ yılmaz ', '{"email": "ali@mail.com", "telefon": "555-123-4567"}', '2023-10-12', '1250.50 TL', 'Elektronik - Laptop'), -- KOPYA (Duplicate) KAYIT
('Zeynep Çelik', 'Sadece text veri var, json degil. tel: 0544-333-22-11', 'InvalidDate', '750 TL', 'Kozmetik - Parfüm');

-- 2. STAR SCHEMA HEDEFLERİ (Load Aşaması İçin)
CREATE TABLE dim_musteri (
    musteri_id SERIAL PRIMARY KEY,
    ad VARCHAR(50),
    soyad VARCHAR(50),
    email VARCHAR(100),
    telefon VARCHAR(20)
);

CREATE TABLE dim_urun (
    urun_id SERIAL PRIMARY KEY,
    kategori VARCHAR(50),
    urun_adi VARCHAR(100)
);

CREATE TABLE fact_satis (
    satis_id SERIAL PRIMARY KEY,
    musteri_id INT REFERENCES dim_musteri(musteri_id),
    urun_id INT REFERENCES dim_urun(urun_id),
    tarih DATE,
    tutar DECIMAL(10,2),
    para_birimi VARCHAR(10)
);

-- 3. ETL SÜRECİNİ YÜRÜTEN STORED PROCEDURE
CREATE OR REPLACE PROCEDURE etl_surecini_baslat() AS $$
DECLARE
    -- Gerekli yerel değişkenler buraya tanımlanabilir
BEGIN
    -- =========================================================================
    -- ADIM 1: DEDUPLICATION (Mükerrer Kayıt Temizliği)
    -- =========================================================================
    -- ROW_NUMBER() window (pencere) fonksiyonu kullanarak, aynı müşteri adı, sipariş tarihi ve ürün detayına sahip 
    -- mükerrer kayıtları grupluyoruz (PARTITION BY). Her grubun kendi içinde bir satır numarası (satir_no) almasını 
    -- sağlıyoruz ve sadece satir_no = 1 olan ilk kayıtları geçici (TEMP) tabloya aktararak kopyaları eliyoruz.
    CREATE TEMP TABLE ham_veri_tekil AS
    SELECT * FROM (
        SELECT *, ROW_NUMBER() OVER (
            PARTITION BY musteri_tam_isim, siparis_tarihi, urun_detay 
            ORDER BY id
        ) as satir_no 
        FROM satislar_ham
    ) sub WHERE satir_no = 1;

    -- =========================================================================
    -- ADIM 2: DIMENSION MUSTERI YÜKLEME (Veri Standardizasyonu)
    -- =========================================================================
    -- Bu adımda string (metin), JSON ve RegEx (Düzenli İfadeler) fonksiyonlarını bir arada kullanarak 
    -- ham verideki düzensizlikleri giderip dim_musteri tablosuna yazıyoruz.
    INSERT INTO dim_musteri (ad, soyad, email, telefon)
    SELECT DISTINCT
        -- INITCAP: İsmin ilk harfini büyük, diğer harflerini küçük yapar.
        -- TRIM: Metnin başındaki ve sonundaki gereksiz boşlukları temizler.
        -- SPLIT_PART: Boşluk karakterine göre ismi böler ve 1. parçasını (Ad) alır.
        INITCAP(TRIM(SPLIT_PART(TRIM(musteri_tam_isim), ' ', 1))) AS ad,
        
        -- SUBSTRING ve POSITION: Boşluk karakterinden sonrasını (Soyad) kesip alır ve UPPER ile tamamen büyük harfe çevirir.
        UPPER(TRIM(SUBSTRING(TRIM(musteri_tam_isim) FROM POSITION(' ' IN TRIM(musteri_tam_isim))))) AS soyad,
        
        -- JSON Parse ve Regex ile E-posta Ayıklama:
        -- LIKE '{%' ile iletişim bilgisinin JSON formatında olup olmadığını kontrol ediyoruz.
        -- JSON ise (::jsonb ->> 'email') operatörüyle doğrudan email değerini çekiyoruz.
        -- Düz metin ise Düzenli İfade (RegEx) kullanarak e-posta kalıbını (SUBSTRING) metnin içinden bulup çıkarıyoruz.
        CASE 
            WHEN iletisim_bilgisi LIKE '{%' THEN iletisim_bilgisi::jsonb ->> 'email'
            ELSE (SUBSTRING(iletisim_bilgisi FROM '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+'))
        END AS email,
        
        -- Regex ile Telefon Numarası Temizleme:
        -- REGEXP_REPLACE fonksiyonundaki '\D' (rakam olmayan her şey) deseniyle, telefon numarasındaki 
        -- boşluk, tire, parantez gibi karakterleri temizleyip sadece ham rakamları elde ediyoruz.
        -- JSON ise içerisinden 'telefon' alanını, düz metin ise 0 ile başlayan telefon kalıbını ayıklıyoruz.
        CASE 
            WHEN iletisim_bilgisi LIKE '{%' THEN REGEXP_REPLACE(iletisim_bilgisi::jsonb ->> 'telefon', '\D', '', 'g')
            ELSE REGEXP_REPLACE(SUBSTRING(iletisim_bilgisi FROM '0[0-9 -]{10,}'), '\D', '', 'g')
        END AS telefon
    FROM ham_veri_tekil;

    -- =========================================================================
    -- ADIM 3: DIMENSION URUN YÜKLEME
    -- =========================================================================
    -- 'Elektronik - Laptop' gibi tek parça halinde gelen ürün detay alanını
    -- SPLIT_PART fonksiyonunu tire (-) işaretine göre bölerek kategori ve ürün adı olarak ayrıştırıyoruz.
    INSERT INTO dim_urun (kategori, urun_adi)
    SELECT DISTINCT
        TRIM(SPLIT_PART(urun_detay, '-', 1)) AS kategori,
        TRIM(SPLIT_PART(urun_detay, '-', 2)) AS urun_adi
    FROM ham_veri_tekil;

    -- =========================================================================
    -- ADIM 4: FACT SATIS YÜKLEME (Lookup ve Veri Tamamlama)
    -- =========================================================================
    -- Temizlenmiş boyut tablolarını (dim_musteri ve dim_urun) isim bazlı eşleştirerek (JOIN) ilişkisel
    -- anahtarları (musteri_id, urun_id) çekiyoruz ve fact_satis tablosuna satış kayıtlarını yüklüyoruz.
    INSERT INTO fact_satis (musteri_id, urun_id, tarih, tutar, para_birimi)
    SELECT 
        dm.musteri_id,
        du.urun_id,
        
        -- Tarih Standardizasyonu ve Hata Yönetimi:
        -- CASE WHEN ile sipariş tarihlerini regex desenleriyle kontrol ediyoruz.
        -- YYYY-MM-DD formatında ise doğrudan DATE tipine çeviriyoruz (CAST).
        -- DD/MM/YYYY veya YYYY/MM/DD formatlarında ise TO_DATE fonksiyonu ile standart tarih formatına dönüştürüyoruz.
        -- "InvalidDate" gibi geçersiz formatlardaki tarihleri ise veritabanı tutarlılığı için NULL olarak işaretliyoruz.
        CASE 
            WHEN siparis_tarihi ~ '^\d{4}-\d{2}-\d{2}$' THEN CAST(siparis_tarihi AS DATE)
            WHEN siparis_tarihi ~ '^\d{2}/\d{2}/\d{4}$' THEN TO_DATE(siparis_tarihi, 'DD/MM/YYYY')
            WHEN siparis_tarihi ~ '^\d{4}/\d{2}/\d{2}$' THEN TO_DATE(siparis_tarihi, 'YYYY/MM/DD')
            ELSE NULL -- Geçersiz tarihler NULL kalır
        END AS tarih,
        
        -- Tutar ve Para Birimi Ayrıştırma:
        -- Metin içindeki rakamları RegEx ile ayıklayıp tutar sütununa DECIMAL olarak yazıyoruz.
        -- Para birimi ('$' veya 'TL') simgelerini tespit edip yeni oluşturduğumuz para_birimi sütununa yazıyoruz.
        CASE
            WHEN satis_tutari = 'NULL' OR satis_tutari IS NULL THEN 0
            ELSE CAST(REGEXP_REPLACE(satis_tutari, '[^\d.]', '', 'g') AS DECIMAL)
        END AS tutar,
        
        CASE
            WHEN satis_tutari LIKE '%$%' THEN 'USD'
            WHEN UPPER(satis_tutari) LIKE '%TL%' THEN 'TRY'
            ELSE 'TRY' -- Varsayılan
        END AS para_birimi
    FROM ham_veri_tekil ht
    JOIN dim_musteri dm ON LOWER(TRIM(dm.ad)) = LOWER(TRIM(SPLIT_PART(TRIM(ht.musteri_tam_isim), ' ', 1)))
    JOIN dim_urun du ON TRIM(du.urun_adi) = TRIM(SPLIT_PART(ht.urun_detay, '-', 2));

END;
$$ LANGUAGE plpgsql;

-- Raporlama için View
CREATE VIEW vw_satis_raporu AS
SELECT 
    f.tarih,
    m.ad || ' ' || m.soyad AS musteri,
    m.telefon,
    u.kategori,
    u.urun_adi,
    f.tutar,
    f.para_birimi
FROM fact_satis f
JOIN dim_musteri m ON m.musteri_id = f.musteri_id
JOIN dim_urun u ON u.urun_id = f.urun_id;
