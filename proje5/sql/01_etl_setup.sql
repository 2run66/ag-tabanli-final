-- 01_etl_setup.sql

-- 1. Kirli Veri Tablosu (Raw Data)
CREATE TABLE ham_veri (
    id SERIAL PRIMARY KEY,
    isim VARCHAR(100),
    telefon VARCHAR(50),
    email VARCHAR(100),
    kayit_tarihi VARCHAR(50)
);

INSERT INTO ham_veri (isim, telefon, email, kayit_tarihi) VALUES 
('   ali YILMAZ  ', '555 123 45 67', 'ALi@gmail.com', '2023-01-15'),
('AYŞE kaya', NULL, 'ayse..kaya@hotmail.com', '15/02/2023'),
('mehmet ', '0532-999-88-77', 'mehmet@sirket', '2023/03/10'),
('', '555-555-5555', NULL, 'InvalidDate');

-- 2. Temizlenmiş Veri Tablosu (Clean Data)
CREATE TABLE temiz_veri (
    id INT PRIMARY KEY,
    ad VARCHAR(50),
    soyad VARCHAR(50),
    telefon VARCHAR(20),
    email VARCHAR(100),
    kayit_tarihi DATE
);

-- 3. ETL Dönüşüm İşlemi (Transformation & Load)
INSERT INTO temiz_veri (id, ad, soyad, telefon, email, kayit_tarihi)
SELECT 
    id,
    -- İsim temizleme (Baştaki sondaki boşlukları at, ilk harfi büyük yap vs)
    INITCAP(TRIM(SPLIT_PART(TRIM(isim), ' ', 1))) AS ad,
    UPPER(TRIM(SUBSTRING(TRIM(isim) FROM POSITION(' ' IN TRIM(isim))))) AS soyad,
    
    -- Telefon formatlama (Rakam harici karakterleri temizle)
    COALESCE(REGEXP_REPLACE(telefon, '\D', '', 'g'), 'Bilinmiyor') AS telefon,
    
    -- Email küçük harfe çevir
    LOWER(TRIM(email)) AS email,
    
    -- Tarih standartlaştırma (Geçersizleri NULL yap)
    CASE 
        WHEN kayit_tarihi ~ '^\d{4}-\d{2}-\d{2}$' THEN CAST(kayit_tarihi AS DATE)
        WHEN kayit_tarihi ~ '^\d{2}/\d{2}/\d{4}$' THEN TO_DATE(kayit_tarihi, 'DD/MM/YYYY')
        WHEN kayit_tarihi ~ '^\d{4}/\d{2}/\d{2}$' THEN TO_DATE(kayit_tarihi, 'YYYY/MM/DD')
        ELSE NULL
    END AS kayit_tarihi
FROM ham_veri
WHERE isim IS NOT NULL AND TRIM(isim) != '';
