# PROJE 2: Veritabanı Yedekleme ve Kapsamlı Felaketten Kurtarma Planı
Bu projede PostgreSQL üzerinde WAL (Write-Ahead Log) arşivleme kullanılarak gerçek bir **Point-in-Time Recovery (PITR)** senaryosu uygulanmıştır.

## Senaryo Adımları ve Detaylar
1. **Arşiv Modu:** Veritabanı oluşturulurken `archive_mode=on` olarak ayarlanmış ve her transaction log dosyası (WAL) `/mnt/archive` dizinine yedeklenmiştir.
2. **Base Backup:** `pg_basebackup` kullanılarak tüm veritabanının anlık bir kopyası `/mnt/backup/base_backup` dizinine alınmıştır.
3. **PITR İçin Hedef Zaman:** Base backup alındıktan sonra yeni veriler girilmiş ve tam bu anın **Zaman Damgası (Timestamp)** not alınmıştır.
4. **Felaket:** Yanlışlıkla veya kötü niyetli olarak `siparisler` tablosu `DROP TABLE` komutuyla silinmiştir.
5. **Geri Yükleme İşlemi (Restore):**
   - Veritabanı kapatıldı.
   - Bozuk veri klasörü (data directory) tamamen silindi.
   - Base backup veri klasörüne kopyalandı.
   - `recovery.signal` dosyası oluşturularak veritabanına kurtarma modunda başlatılması talimatı verildi.
   - `postgresql.auto.conf` dosyasına `restore_command` ve `recovery_target_time` (Not alınan zaman damgası) eklendi.
6. **Sonuç:** Veritabanı başlatıldığında WAL dosyalarını arşivden okuyarak belirtilen milisaniyeye kadar olan tüm işlemleri baştan oynattı (Replay) ve `DROP TABLE` komutundan hemen önce durdu. Böylece sıfır veri kaybı sağlandı.
