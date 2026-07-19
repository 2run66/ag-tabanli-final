-- 01_security_setup.sql
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Tablolar
CREATE TABLE calisanlar (
    id SERIAL PRIMARY KEY,
    ad VARCHAR(50),
    departman VARCHAR(50),
    maas DECIMAL(10,2),
    sifre_hash TEXT
);

INSERT INTO calisanlar (ad, departman, maas, sifre_hash) VALUES 
('Müdür', 'Yönetim', 25000.00, crypt('gizlisifre', gen_salt('bf'))),
('Ali', 'IT', 12000.00, crypt('ali123', gen_salt('bf'))),
('Ayşe', 'IK', 11000.00, crypt('ayse123', gen_salt('bf')));

-- Roller ve Yetkiler
CREATE ROLE it_rolu NOLOGIN;
CREATE ROLE ik_rolu NOLOGIN;

GRANT SELECT ON calisanlar TO it_rolu;
GRANT SELECT, UPDATE ON calisanlar TO ik_rolu;

-- Row Level Security (RLS)
ALTER TABLE calisanlar ENABLE ROW LEVEL SECURITY;

CREATE POLICY it_policy ON calisanlar FOR SELECT TO it_rolu USING (departman = 'IT');
CREATE POLICY ik_policy ON calisanlar FOR ALL TO ik_rolu USING (departman = 'IK');

-- Kullanıcılar
CREATE USER ali_kullanicisi WITH PASSWORD 'password123';
GRANT it_rolu TO ali_kullanicisi;
