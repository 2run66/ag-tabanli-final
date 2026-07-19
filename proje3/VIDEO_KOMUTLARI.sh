#!/bin/bash
# PROJE 3 - VİDEO KOMUTLARI (Güvenlik, RLS, Audit, SQL Injection)
function pause(){
   read -p "Devam etmek için [ENTER] tuşuna basın..."
}
docker compose down -v
echo "=== ADIM 1: Veritabanını Başlatma ==="
# docker compose up -d: Güvenlik senaryomuz için izole bir PostgreSQL container'ı başlatır.
docker compose up -d
echo "PostgreSQL'in hazır olması bekleniyor..."
sleep 10
# 01_advanced_security.sql: Şifreleme eklentisini (pgcrypto), tabloları, RLS politikalarını, audit log yapısını ve SQL injection zafiyetli fonksiyonları kurar.
docker exec pg16_security_adv psql -U admin -d guvenlik_db -f /sql/01_advanced_security.sql
pause

echo "=== ADIM 2: Şifrelenmiş Verileri (PGCrypto) Görme ==="
# pgcrypto eklentisi veritabanı seviyesinde şifreleme sağlar.
# 1. Kredi kartı verisi select edildiğinde ham olarak değil, anlamsız şifrelenmiş binary/text (crypt) olarak döner:
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT id, kredi_karti, bakiye FROM finans_verileri;"
# 2. PGP_SYM_DECRYPT fonksiyonu ve gizli anahtarımız ('SüperGizliAnahtar') kullanılarak şifreli veri çözülür:
echo "Doğru anahtar ile şifreyi çözme işlemi:"
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT id, PGP_SYM_DECRYPT(kredi_karti::bytea, 'SüperGizliAnahtar') AS acik_kredi_karti, bakiye FROM finans_verileri;"
pause

echo "=== ADIM 3: Row Level Security (RLS) Testi ==="
# Row Level Security (Satır Bazlı Güvenlik), kullanıcının yetkisine göre tablodaki sadece belirli satırları görmesini sağlar.
# 'satis_usr' (satış personeli) kullanıcısı ile bağlanıyoruz.
# RLS politikamız gereği bu kullanıcı sadece departmanı 'satis' olan satırları görebilir. Yönetici (yonetici) satırlarını göremez:
docker exec pg16_security_adv psql -U satis_usr -d guvenlik_db -c "SELECT * FROM finans_verileri;"
pause

echo "=== ADIM 4: Trigger Tabanlı Audit Logging ==="
# Veritabanında yapılan kritik değişiklikleri (UPDATE/DELETE) izlemek için Audit Log mekanizması.
# 1. Admin olarak bir çalışanın bakiyesini güncelliyoruz:
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "UPDATE finans_verileri SET bakiye = 75000.00 WHERE id = 1;"
# 2. Yazdığımız Trigger devreye girer ve eski bakiye ile yeni bakiyeyi JSONB olarak denetim tablosuna yazar:
echo "Audit Log tablosuna düşen kayıt:"
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT tablo_adi, islem_tipi, eski_deger->>'bakiye' AS eski_bakiye, yeni_deger->>'bakiye' AS yeni_bakiye, islem_yapan FROM audit_log;"
pause

echo "=== ADIM 5: SQL Injection Atağı (Zafiyetli Fonksiyon) ==="
# SQL Injection: Kullanıcı girdisinin filtrelenmeden doğrudan dinamik SQL string'ine eklenmesiyle oluşur.
# 1. Normal/Güvenli Kullanıcı Sorgusu:
echo "Normal kullanım (ahmet_satis kullanıcısının bakiyesi soruluyor):"
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT * FROM bakiye_getir_zayif('ahmet_satis');"
pause
# 2. SQL Injection Saldırısı:
# Kullanıcı adı kısmına 'ahmet_satis' OR '1'='1' göndererek WHERE koşulunu bypass ediyoruz.
# Böylece zafiyetli fonksiyon tüm finans verilerini dışarı sızdırıyor:
echo "Hacker sisteme müdahale ediyor (SQL Injection)..."
echo "Kullanıcı adı olarak 'ahmet_satis'' OR ''1''=''1' gönderiliyor."
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT * FROM bakiye_getir_zayif('ahmet_satis'' OR ''1''=''1');"
echo "Tüm bakiyeler ele geçirildi!"
pause

echo "=== ADIM 6: SQL Injection Çözümü (Güvenli Fonksiyon) ==="
# Çözüm: Değişkenleri dinamik string olarak birleştirmek yerine, PARAMETRİK sorgu (USING) kullanmaktır.
# Aynı SQL injection atağı güvenli fonksiyona yapıldığında parametre string olarak kabul edilir ve atak engellenir:
echo "Aynı atak güvenli fonksiyona yapılıyor:"
docker exec pg16_security_adv psql -U admin -d guvenlik_db -c "SELECT * FROM bakiye_getir_guvenli('ahmet_satis'' OR ''1''=''1');"
echo "Sonuç boş. Parametrik yapı (EXECUTE ... USING) injection'ı engelledi."

echo "Test tamamlandı. (Temizlemek için: docker compose down -v)"
