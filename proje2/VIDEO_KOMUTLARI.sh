#!/bin/bash
# PROJE 2 - VİDEO KOMUTLARI (Kapsamlı PITR & Restore)
# Video çekimi için interaktif script. Devam etmek için ENTER'a basın.
function pause(){
   read -p "Devam etmek için [ENTER] tuşuna basın..."
}

echo "=== ADIM 1: Eski Verileri Temizleme ve Veritabanını Başlatma ==="
docker compose down -v
# Volume'leri oluşturup yazma izinlerini postgres (999) kullanıcısına veriyoruz
docker volume create proje2_pg_archive_pitr
docker volume create proje2_pg_backup_pitr
docker run --rm -v proje2_pg_archive_pitr:/archive -v proje2_pg_backup_pitr:/backup busybox chown -R 999:999 /archive /backup
docker compose up -d
echo "PostgreSQL'in hazır olması bekleniyor..."
sleep 15
pause

echo "=== ADIM 2: İlk Verileri Kontrol Etme ==="
docker exec pg16_pitr psql -U admin -d e_ticaret_db -f /sql/01_init.sql
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "SELECT * FROM siparisler;"
pause

echo "=== ADIM 3: Base Backup (Tam Yedek) Alınması ==="
# pg_basebackup: Veritabanının fiziksel olarak tam bir kopyasını (base backup) alır.
# Parametrelerin Anlamları:
#   -U admin                  : İşlemi gerçekleştirecek yetkili veritabanı kullanıcısı.
#   -D /mnt/backup/base_backup: Yedeğin yazılacağı hedef dizin (Backup volume'üne yazılır).
#   -F p                      : Format Plain (Klasör yapısı). Veri klasörünün birebir kopyasını oluşturur.
#   -X stream                 : Yedekleme esnasında oluşan WAL (Write-Ahead Log) kayıtlarını da eş zamanlı akışla (stream) yedeğe dahil eder.
docker exec pg16_pitr pg_basebackup -U admin -D /mnt/backup/base_backup -F p -X stream
echo "Backup başarıyla /mnt/backup/base_backup dizinine alındı."
pause

echo "=== ADIM 4: Veritabanında Yeni İşlemler (Backup Sonrası) ==="
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "INSERT INTO siparisler (musteri_id, toplam_tutar, durum) VALUES (3, 5000.00, 'Kargoda');"
# Kritik zaman damgasını alıyoruz (İşlemin commit edilmesini garantilemek için 2 saniye ekliyoruz)
CRITICAL_TIME=$(docker exec pg16_pitr psql -U admin -d e_ticaret_db -t -c "SELECT to_char(current_timestamp + interval '2 seconds', 'YYYY-MM-DD HH24:MI:SS');" | xargs)
# WAL dosyasının arşive yazılması için WAL segmentini manuel tetikliyoruz
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "SELECT pg_switch_wal();"
echo "Yeni veri eklendi. Kritik Zaman Damgası: ${CRITICAL_TIME}"
sleep 2
pause

echo "=== ADIM 5: FELAKET (Verilerin Silinmesi) ==="
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "DROP TABLE siparisler CASCADE;"
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "\dt siparisler;"
echo "TABLO SİLİNDİ! Tüm sipariş verileri gitti."
pause

echo "=== ADIM 6: Point-in-Time Recovery (PITR) Süreci ==="
echo "1. PostgreSQL container'ları durduruluyor..."
docker compose down
echo "2. Bozulan data klasörü temizleniyor ve Base Backup geri yükleniyor..."
# Veri dizinindeki tüm dosyaları silip, temizlediğimiz yere fiziksel yedeği kopyalıyoruz:
#   -v proje2_pg_data_pitr:/data      : Aktif PostgreSQL veri diskini (volume) container içindeki /data klasörüne bağlar.
#   -v proje2_pg_backup_pitr:/backup  : Aldığımız tam yedeğin durduğu diski /backup klasörüne bağlar.
#   rm -rf /data/*                    : Aktif (ve felaket sonucu bozulan) veritabanı klasöründeki her şeyi tamamen siler.
#   cp -a /backup/base_backup/* /data/: Fiziksel yedekteki (ADIM 3'teki durum) tüm veritabanı dosyalarını aktif veri klasörüne kopyalar.
docker run --rm -v proje2_pg_data_pitr:/data -v proje2_pg_backup_pitr:/backup busybox sh -c "rm -rf /data/* && cp -a /backup/base_backup/* /data/"
echo "3. Recovery (kurtarma) yapılandırması ayarlanıyor..."
# Postgres'in kurtarma (recovery) modunda açılmasını sağlayan ayarları yapıyoruz:
#   1. touch recovery.signal    : Veritabanının kurtarma modunda başlayacağını belirten tetikleyici dosya.
#   2. restore_command          : Arşivlenmiş WAL dosyalarını kurtarma sırasında nereden kopyalayacağını söyler (%f: dosya adı, %p: hedef yol).
#   3. recovery_target_time     : Kurtarma işleminin tam olarak hangi saniyede durdurulacağını belirtir (bizim kritik zamanımız).
#   4. recovery_target_action   : Hedef zamana ulaşıldığında veritabanını otomatik olarak normal (yazılabilir) moda geçirir (promote eder).
#   5. chown -R 999:999         : Dosya yetkilerini postgres (999) kullanıcısına vererek izin hatası almayı önler.
docker run --rm -v proje2_pg_data_pitr:/data busybox sh -c "touch /data/recovery.signal && echo \"restore_command = 'cp /mnt/archive/%f %p'\" >> /data/postgresql.auto.conf && echo \"recovery_target_time = '${CRITICAL_TIME}'\" >> /data/postgresql.auto.conf && echo \"recovery_target_action = 'promote'\" >> /data/postgresql.auto.conf && chown -R 999:999 /data"

echo "4. PostgreSQL Kurtarma Modunda Başlatılıyor..."
docker compose up -d
echo "Veritabanının verileri işlemesi ve ayağa kalkması bekleniyor (PITR)..."
sleep 15
pause

echo "=== ADIM 7: Kurtarılan Verilerin Kontrolü ==="
docker exec pg16_pitr psql -U admin -d e_ticaret_db -c "SELECT * FROM siparisler;"
echo "Siparişler tablosu, felaket anından hemen önceki haline başarıyla geri döndürüldü!"

echo "Test tamamlandı. (Temizlemek için: docker compose down -v)"
