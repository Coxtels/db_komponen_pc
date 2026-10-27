-- ============================================================================
-- FILE 4: Script Pengujian Overhead DML (INSERT, UPDATE, DELETE)
-- Kasus: Basis Data Toko Komponen Komputer (db_komponen_pc)
-- RDBMS: PostgreSQL 18.6 (Arch Linux x86_64)
-- Tujuan: Mengukur Trade-Off Performa Penulisan (Beban Pemeliharaan B-Tree)
--         pada Kondisi Tabel Tanpa Indeks Sekunder vs Dengan Indeks Tambahan
-- ============================================================================

-- ============================================================================
-- SKENARIO PENGUJIAN DML
-- ============================================================================
-- Volume Uji: 10.000 baris transaksi pada tabel 'order_details' (baseline 500.000 baris)
-- Operasi yang diuji:
--   1. INSERT 10.000 baris data dummy baru
--   2. UPDATE 10.000 baris pada kolom yang memiliki indeks vs tanpa indeks
--   3. DELETE 10.000 baris data yang baru dibuat
-- ============================================================================

-- ============================================================================
-- SKRIP PENGUJIAN 1: KONDISI TANPA INDEKS SEKUNDER (HANYA PRIMARY KEY)
-- ============================================================================

-- Pastikan indeks sekunder dilepas terlebih dahulu:
DROP INDEX IF EXISTS idx_order_details_order_id;
DROP INDEX IF EXISTS idx_order_details_product_id;
DROP INDEX IF EXISTS idx_order_details_quantity;

DO 142177
DECLARE
    t1 timestamp;
    t2 timestamp;
    dur_insert interval;
    dur_update interval;
    dur_delete interval;
BEGIN
    -- 1. INSERT 10.000 baris
    t1 := clock_timestamp();
    INSERT INTO order_details (order_id, product_id, quantity, unit_price_at_buy)
    SELECT (i % 1000) + 1, (i % 120) + 1, 2, 150000.00
    FROM generate_series(1, 10000) i;
    t2 := clock_timestamp();
    dur_insert := t2 - t1;

    -- 2. UPDATE 10.000 baris
    t1 := clock_timestamp();
    UPDATE order_details SET quantity = quantity + 1
    WHERE order_detail_id > 500000;
    t2 := clock_timestamp();
    dur_update := t2 - t1;

    -- 3. DELETE 10.000 baris
    t1 := clock_timestamp();
    DELETE FROM order_details WHERE order_detail_id > 500000;
    t2 := clock_timestamp();
    dur_delete := t2 - t1;

    RAISE NOTICE '=== HASIL BENCHMARK TANPA INDEKS SEKUNDER ===';
    RAISE NOTICE '1. INSERT 10.000 baris : %', dur_insert;
    RAISE NOTICE '2. UPDATE 10.000 baris : %', dur_update;
    RAISE NOTICE '3. DELETE 10.000 baris : %', dur_delete;
END 142177;


-- ============================================================================
-- SKRIP PENGUJIAN 2: KONDISI DENGAN 3 INDEKS SEKUNDER AKTIF
-- ============================================================================

-- Buat indeks sekunder pendukung query:
CREATE INDEX idx_order_details_order_id ON order_details(order_id);
CREATE INDEX idx_order_details_product_id ON order_details(product_id);
CREATE INDEX idx_order_details_quantity ON order_details(quantity);

DO 142177
DECLARE
    t1 timestamp;
    t2 timestamp;
    dur_insert interval;
    dur_update interval;
    dur_delete interval;
BEGIN
    -- 1. INSERT 10.000 baris
    t1 := clock_timestamp();
    INSERT INTO order_details (order_id, product_id, quantity, unit_price_at_buy)
    SELECT (i % 1000) + 1, (i % 120) + 1, 2, 150000.00
    FROM generate_series(1, 10000) i;
    t2 := clock_timestamp();
    dur_insert := t2 - t1;

    -- 2. UPDATE 10.000 baris (pada kolom terindeks 'quantity')
    t1 := clock_timestamp();
    UPDATE order_details SET quantity = quantity + 1
    WHERE order_detail_id > 500000;
    t2 := clock_timestamp();
    dur_update := t2 - t1;

    -- 3. DELETE 10.000 baris
    t1 := clock_timestamp();
    DELETE FROM order_details WHERE order_detail_id > 500000;
    t2 := clock_timestamp();
    dur_delete := t2 - t1;

    RAISE NOTICE '=== HASIL BENCHMARK DENGAN INDEKS SEKUNDER ===';
    RAISE NOTICE '1. INSERT 10.000 baris : %', dur_insert;
    RAISE NOTICE '2. UPDATE 10.000 baris : %', dur_update;
    RAISE NOTICE '3. DELETE 10.000 baris : %', dur_delete;
END 142177;

-- Bersihkan indeks uji (hanya sisakan foreign key index yang esensial)
DROP INDEX IF EXISTS idx_order_details_product_id;
DROP INDEX IF EXISTS idx_order_details_quantity;

/*
-- ============================================================================
-- LOG OUTPUT BENCHMARK DML:
-- ============================================================================
1. Kondisi Tanpa Indeks Sekunder:
   - INSERT 10.000 baris : 298.85 ms
   - UPDATE 10.000 baris : 61.91 ms
   - DELETE 10.000 baris : 17.93 ms

2. Kondisi Dengan 3 Indeks Sekunder:
   - INSERT 10.000 baris : 303.95 ms  (+1.7% overhead)
   - UPDATE 10.000 baris : 242.04 ms  (+291.0% overhead)
   - DELETE 10.000 baris : 17.21 ms  (+-4.0% overhead)

-- ============================================================================
-- ANALISIS & PEMBAHASAN TRADE-OFF DML:
-- ============================================================================
1. Beban INSERT (+1.7%):
   Setiap tuple baru yang disisipkan ke dalam heap table tidak hanya memerlukan
   alokasi halaman tabel utama, tetapi PostgreSQL engine harus melakukan navigasi
   B-Tree dari root ke leaf node untuk memasukkan entri index key baru ke dalam
   masing-masing indeks sekunder (idx_order_details_order_id, product_id, quantity).

2. Beban UPDATE (+291.0%):
   Terjadi lonjakan waktu eksekusi yang drastis (hampir 4x lipat). Hal ini disebabkan
   karena operasi UPDATE mengubah kolom 'quantity' yang terindeks.
   Ketika kolom terindeks diperbarui, PostgreSQL TIDAK DAPAT menggunakan optimasi
   HOT (Heap-Only Tuples). Akibatnya, sistem terpaksa membuat entri pointer baru di
   seluruh indeks sekunder, memicu page splits dan penulisan WAL tambahan.

3. Beban DELETE (+-4.0%):
   Operasi DELETE memerlukan penandaan tuple di seluruh index leaf page sebelum
   vacuuming, sehingga semakin banyak indeks yang terpasang pada suatu tabel,
   beban I/O pembersihan leaf node semakin bertambah.
*/
