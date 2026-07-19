-- 01_init.sql
CREATE TABLE musteriler (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(100),
    email VARCHAR(100) UNIQUE,
    kayit_tarihi TIMESTAMP DEFAULT current_timestamp
);
CREATE TABLE siparisler (
    id SERIAL PRIMARY KEY,
    musteri_id INT REFERENCES musteriler(id),
    toplam_tutar DECIMAL(10, 2),
    durum VARCHAR(50),
    siparis_tarihi TIMESTAMP DEFAULT current_timestamp
);
INSERT INTO musteriler (ad, email)
VALUES ('Ahmet Yılmaz', 'ahmet@mail.com'),
    ('Ayşe Demir', 'ayse@mail.com'),
    ('Mehmet Kaya', 'mehmet@mail.com');
INSERT INTO siparisler (musteri_id, toplam_tutar, durum)
VALUES (1, 1500.00, 'Tamamlandı'),
    (2, 450.50, 'Hazırlanıyor'),
    (1, 100.00, 'İptal');