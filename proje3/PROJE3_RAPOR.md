# PROJE 3: İleri Seviye Veritabanı Güvenliği Raporu

## 1. Veri Şifreleme (Data Encryption)
Kullanıcı şifreleri tek yönlü hashing algoritması (bcrypt) ile şifrelenirken, Kredi Kartı numarası gibi sonradan görülmesi gereken veriler `PGP_SYM_ENCRYPT` (Simetrik Şifreleme) ile AES standartlarında şifrelenerek saklanmıştır.

## 2. Row Level Security (RLS)
Sadece tablo bazlı `GRANT/DENY` ile kalınmamış, satır bazlı erişim kontrolü etkinleştirilmiştir. Satış temsilcisine sadece kendi departmanının kayıtlarını okuma ve güncelleme yetkisi verilmiş, `WITH CHECK` koşuluyla RLS bypass edilmesi engellenmiştir.

## 3. Trigger Tabanlı Audit Log (Denetim Kaydı)
Hassas tablolarda (finans_verileri) yapılan her UPDATE veya DELETE işlemi bir PostgreSQL Trigger'ı tarafından yakalanarak `audit_log` tablosuna yazılmaktadır. Değişikliğin eski hali (`OLD`), yeni hali (`NEW`) JSONB formatında kaydedilmiş, işlemi yapan kullanıcı (`current_user`) not edilmiştir.

## 4. SQL Injection Zafiyeti ve Çözümü
Dinamik SQL oluşturulurken parametrelerin doğrudan string birleştirmesi (Concatenation - `||`) ile koda dahil edilmesi ciddi güvenlik açıklarına yol açar. Projede bu durum simüle edilmiş ve tüm tablonun `OR '1'='1'` taktiği ile çekilebildiği gösterilmiştir. Çözüm olarak değişkenlerin stringe eklenmeyip `$1` gibi yer tutucularla ve `USING` ifadesi ile PostgreSQL motoruna parametre olarak geçirildiği güvenli bir mimari oluşturulmuştur.
