-- 01_advanced_security.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Tablolar
CREATE TABLE kullanicilar (
    id SERIAL PRIMARY KEY,
    kullanici_adi VARCHAR(50) UNIQUE,
    sifre_hash TEXT,
    rol VARCHAR(20)
);

CREATE TABLE finans_verileri (
    id SERIAL PRIMARY KEY,
    kullanici_id INT REFERENCES kullanicilar(id),
    kredi_karti TEXT, -- Şifrelenmiş tutulacak
    bakiye DECIMAL(15,2),
    departman VARCHAR(20)
);

-- 2. Audit Log Tablosu ve Trigger
CREATE TABLE audit_log (
    log_id SERIAL PRIMARY KEY,
    tablo_adi VARCHAR(50),
    islem_tipi VARCHAR(10),
    eski_deger JSONB,
    yeni_deger JSONB,
    islem_tarihi TIMESTAMP DEFAULT current_timestamp,
    islem_yapan VARCHAR(50) DEFAULT current_user
);

CREATE OR REPLACE FUNCTION audit_trigger_func() RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'UPDATE' THEN
        INSERT INTO audit_log (tablo_adi, islem_tipi, eski_deger, yeni_deger)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb);
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        INSERT INTO audit_log (tablo_adi, islem_tipi, eski_deger)
        VALUES (TG_TABLE_NAME, TG_OP, row_to_json(OLD)::jsonb);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER finans_audit_trigger
AFTER UPDATE OR DELETE ON finans_verileri
FOR EACH ROW EXECUTE FUNCTION audit_trigger_func();

-- 3. Veri Ekleme (Şifreleme ile)
INSERT INTO kullanicilar (kullanici_adi, sifre_hash, rol) VALUES 
('ahmet_satis', crypt('Sifre123!', gen_salt('bf', 8)), 'satis'),
('ayse_yonetici', crypt('Admin456*', gen_salt('bf', 8)), 'yonetici');

-- Kredi kartı PGP ile şifreleniyor
INSERT INTO finans_verileri (kullanici_id, kredi_karti, bakiye, departman) VALUES 
(1, PGP_SYM_ENCRYPT('4545-1234-5678-9999', 'SüperGizliAnahtar'), 50000.00, 'satis'),
(2, PGP_SYM_ENCRYPT('5555-4444-3333-2222', 'SüperGizliAnahtar'), 150000.00, 'yonetici');

-- 4. Rol ve Yetkilendirme
CREATE ROLE satis_rolu;
CREATE ROLE yonetici_rolu;

GRANT SELECT ON kullanicilar TO satis_rolu, yonetici_rolu;
GRANT SELECT, UPDATE ON finans_verileri TO satis_rolu;
GRANT ALL ON finans_verileri TO yonetici_rolu;

-- 5. Row Level Security (RLS)
ALTER TABLE finans_verileri ENABLE ROW LEVEL SECURITY;

-- Satış personeli sadece kendi departmanındaki (satis) verileri görebilir ve GÜNCELLEYEBİLİR
CREATE POLICY satis_gorme_politikasi ON finans_verileri FOR SELECT TO satis_rolu USING (departman = 'satis');
CREATE POLICY satis_guncelleme_politikasi ON finans_verileri FOR UPDATE TO satis_rolu USING (departman = 'satis') WITH CHECK (departman = 'satis');

-- Yönetici her şeyi görebilir
CREATE POLICY yonetici_politikasi ON finans_verileri FOR ALL TO yonetici_rolu USING (true);

CREATE USER satis_usr WITH PASSWORD '123';
GRANT satis_rolu TO satis_usr;

-- 6. ZAFİYETLİ FONKSİYON (SQL Injection Demo İçin)
CREATE OR REPLACE FUNCTION bakiye_getir_zayif(kullanici_isim VARCHAR) RETURNS TABLE(bakiye DECIMAL) AS $$
DECLARE
    sorgu TEXT;
BEGIN
    -- TEHLİKELİ: Parametre doğrudan SQL stringine ekleniyor (Concatenation)
    sorgu := 'SELECT f.bakiye FROM finans_verileri f JOIN kullanicilar k ON k.id = f.kullanici_id WHERE k.kullanici_adi = ''' || kullanici_isim || '''';
    RETURN QUERY EXECUTE sorgu;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- GÜVENLİ FONKSİYON
CREATE OR REPLACE FUNCTION bakiye_getir_guvenli(kullanici_isim VARCHAR) RETURNS TABLE(bakiye DECIMAL) AS $$
BEGIN
    -- GÜVENLİ: Parametrik yapı kullanımı
    RETURN QUERY EXECUTE 'SELECT f.bakiye FROM finans_verileri f JOIN kullanicilar k ON k.id = f.kullanici_id WHERE k.kullanici_adi = $1' USING kullanici_isim;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
