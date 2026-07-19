#!/bin/bash
# PROJE 5 - VİDEO KOMUTLARI (Gelişmiş ETL, RegEx, JSON, Deduplication)
function pause(){
   read -p "Devam etmek için [ENTER] tuşuna basın..."
}
docker compose down -v
echo "=== ADIM 1: Veritabanını Başlatma ==="
# docker compose up -d: ETL projemiz için yalıtılmış PostgreSQL container'ını ayağa kaldırır.
docker compose up -d
echo "PostgreSQL'in hazır olması bekleniyor..."
sleep 10
# 01_advanced_etl.sql: Kirli ham veri tablolarını, hedef boyut/fact tablolarını ve ETL Stored Procedure'ünü oluşturur.
docker exec pg16_etl_adv psql -U admin -d dwh_db -f /sql/01_advanced_etl.sql
pause

echo "=== ADIM 2: Kirli Veri Kaynağı (Extract - Veri Çıkarma) ==="
# Extract (Veri Çıkarma) Aşaması:
# Dış sistemlerden gelen, tamamen kirli verileri ham tabloya çekiyoruz.
# Tablodaki sorunlar:
#   1. İsimlerde gereksiz boşluklar ve karmaşık büyük/küçük harfler var.
#   2. İletişim bilgileri bazen düzgün JSON, bazen sadece düz metin (email/telefon karışık).
#   3. Sipariş tarihleri farklı formatlarda (YYYY-MM-DD, DD/MM/YYYY, YYYY/MM/DD ve geçersiz tarihler).
#   4. Tutar hanesinde para birimi simgeleri (TL, $) ve metinsel NULL ifadeler var.
#   5. Aynı kayıttan ikişer adet var (Mükerrer/Duplicate veri).
docker exec pg16_etl_adv psql -U admin -d dwh_db -c "SELECT * FROM satislar_ham;"
pause

echo "=== ADIM 3: ETL Sürecini Başlatma (Transform & Load - Dönüştürme ve Yükleme) ==="
# Transform & Load (Dönüştürme ve Yükleme) Aşaması:
# etl_surecini_baslat() Stored Procedure'ü çalıştırılarak tüm veri temizleme ve Yıldız Şema (Star Schema) yükleme kuralları işletilir:
#   - Tekilleştirme (Deduplication): ROW_NUMBER() ile çift kayıtlar temizlenir.
#   - Metin Düzeltme: TRIM ve INITCAP ile isimler standartlaştırılır.
#   - RegEx & JSON: JSON alanlar ayrıştırılır, düz metinlerden RegEx ile email/telefon ayıklanır.
#   - Veri Tipi Dönüşümü: Tutarlardaki rakamlar temizlenip sayıya, para birimleri ('$' ve 'TL') ise USD/TRY olarak yeni sütuna ayrılır, tarihler DATE tipine dönüştürülür.
echo "Stored Procedure tetikleniyor..."
docker exec pg16_etl_adv psql -U admin -d dwh_db -c "CALL etl_surecini_baslat();"
echo "İşlem başarılı."
pause

echo "=== ADIM 4: Temizlenmiş Boyut (Dimension) Tabloları ==="
# Load (Yükleme) sonrasında ilişkisel veri ambarı modelindeki Boyut (Dimension) tablolarını kontrol ediyoruz.
# 1. dim_musteri: İsimler ad-soyad ayrılmış, emailler küçük harf yapılmış, telefonlar sadece rakamlardan oluşacak şekilde temizlenmiştir.
docker exec pg16_etl_adv psql -U admin -d dwh_db -c "SELECT * FROM dim_musteri;"
pause
# 2. dim_urun: Ürün detay metninden kategori ve ürün adı ayrıştırılarak eklenmiştir.
echo "-- Ürünler (Kategori ve İsim ayrıştırıldı) --"
docker exec pg16_etl_adv psql -U admin -d dwh_db -c "SELECT * FROM dim_urun;"
pause

echo "=== ADIM 5: Fact Tablosu ve Raporlama ==="
# Fact (Gerçek) tablosu ve rapor görünümü (View) kontrolü.
# fact_satis: Boyut tablolarındaki anahtarlarla (Foreign Key) ilişkilendirilmiş, tutar ve para birimleri (USD, TRY) ayrıştırılmış ve tarihleri DATE formatına çevrilmiş nihai satış verilerini tutar.
# vw_satis_raporu: Yıldız Şemadaki tabloları join ederek temiz rapor sunar.
docker exec pg16_etl_adv psql -U admin -d dwh_db -c "SELECT * FROM vw_satis_raporu;"

echo "Test tamamlandı. (Temizlemek için: docker compose down -v)"
