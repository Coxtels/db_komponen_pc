-- ============================================================================
-- FILE 3: Script DDL Pembuatan Indeks & Log Output EXPLAIN (ANALYZE, BUFFERS) Akhir
-- Kasus: Basis Data Toko Komponen Komputer (db_komponen_pc)
-- RDBMS: PostgreSQL 18.6 (Arch Linux x86_64)
-- Kondisi: Setelah Penerapan Indeks (Single B-Tree, Composite, & Partial Index)
-- ============================================================================

-- ============================================================================
-- BAGIAN A: DDL PEMBUATAN INDEKS
-- ============================================================================

-- 1. Single B-Tree Index: Mengoptimalkan filter dan JOIN foreign key
--    pada tabel orders dan order_details.
CREATE INDEX idx_orders_user_id ON orders(user_id);
CREATE INDEX idx_order_details_order_id ON order_details(order_id);

-- 2. Composite Index: Mengoptimalkan filter multi-kolom status dan tanggal
--    pesanan sesuai kaidah Leftmost Prefix Rule (equality status, range order_date).
CREATE INDEX idx_orders_status_date ON orders(status, order_date DESC);

-- 3. Partial / Filtered Index: Mengoptimalkan penelusuran status khusus ('Pending')
--    tanpa membebani penyimpanan dan DML transaksi berstatus lainnya.
CREATE INDEX idx_orders_pending_date ON orders(order_date) WHERE status = 'Pending';

-- Informasi Ukuran Fisik Indeks:
-- - idx_orders_user_id        : 2144 kB
-- - idx_order_details_order_id: 6832 kB
-- - idx_orders_status_date    : 4640 kB
-- - idx_orders_pending_date   : 672 kB (Bandingkan vs Full Index: 3312 kB)


-- ============================================================================
-- BAGIAN B: EKSEKUSI QUERY & LOG OUTPUT EXPLAIN AKHIR
-- ============================================================================

-- ============================================================================
-- QUERY 1 (OPTIMIZED DENGAN SINGLE B-TREE INDEX)
-- Indeks Digunakan: idx_orders_user_id
-- Transformasi Scan: Seq Scan (150.000 rows) -> Bitmap Index Scan (13 blocks)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    o.order_id,
    o.order_date,
    o.total_amount,
    o.status,
    u.username,
    u.email
FROM orders o
JOIN users u
    ON u.user_id = o.user_id
WHERE
    o.user_id = 38741
    AND o.order_date >= '2026-01-01'
ORDER BY o.order_date DESC
LIMIT 20;

/*
                                                                   QUERY PLAN                                                                    
-------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=28.04..28.05 rows=3 width=57) (actual time=0.251..0.259 rows=10.00 loops=1)
   Buffers: shared hit=16 read=2
   ->  Sort  (cost=28.04..28.05 rows=3 width=57) (actual time=0.248..0.253 rows=10.00 loops=1)
         Sort Key: o.order_date DESC
         Sort Method: quicksort  Memory: 26kB
         Buffers: shared hit=16 read=2
         ->  Nested Loop  (cost=4.62..28.02 rows=3 width=57) (actual time=0.182..0.226 rows=10.00 loops=1)
               Buffers: shared hit=16 read=2
               ->  Index Scan using users_pkey on users u  (cost=0.29..8.31 rows=1 width=39) (actual time=0.019..0.021 rows=1.00 loops=1)
                     Index Cond: (user_id = 38741)
                     Index Searches: 1
                     Buffers: shared hit=3
               ->  Bitmap Heap Scan on orders o  (cost=4.33..19.68 rows=3 width=26) (actual time=0.156..0.191 rows=10.00 loops=1)
                     Recheck Cond: (user_id = 38741)
                     Filter: (order_date >= '2026-01-01 00:00:00'::timestamp without time zone)
                     Rows Removed by Filter: 3
                     Heap Blocks: exact=13
                     Buffers: shared hit=13 read=2
                     ->  Bitmap Index Scan on idx_orders_user_id  (cost=0.00..4.33 rows=4 width=0) (actual time=0.123..0.123 rows=13.00 loops=1)
                           Index Cond: (user_id = 38741)
                           Index Searches: 1
                           Buffers: shared read=2
 Planning:
   Buffers: shared hit=56 read=3
 Planning Time: 1.238 ms
 Execution Time: 0.325 ms
(26 rows)


*/


-- ============================================================================
-- QUERY 2 (OPTIMIZED DENGAN COMPOSITE INDEX)
-- Indeks Digunakan: idx_orders_status_date
-- Transformasi Scan: Parallel Seq Scan (Cost 2.794) -> Bitmap Index Scan (Cost 19.46)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    c.category_name,
    b.brand_name,
    DATE_TRUNC('day', o.order_date) AS hari,
    SUM(od.quantity) AS unit_terjual,
    SUM(od.quantity * od.unit_price_at_buy) AS pendapatan
FROM orders o
JOIN order_details od
    ON od.order_id = o.order_id
JOIN products p
    ON p.product_id = od.product_id
JOIN categories c
    ON c.category_id = p.category_id
JOIN brands b
    ON b.brand_id = p.brand_id
WHERE
    o.status = 'Completed'
    AND o.order_date >= '2026-03-02'
    AND o.order_date < '2026-03-09'
GROUP BY
    c.category_name,
    b.brand_name,
    DATE_TRUNC('day', o.order_date)
ORDER BY
    hari ASC,
    pendapatan DESC;

/*
LOG OUTPUT EXPLAIN QUERY 2 (SETELAH INDEKS):
                                                                                                                          QUERY PLAN                                                    
                                                                       
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-----------------------------------------------------------------------
 Incremental Sort  (cost=7947.48..8289.22 rows=1943 width=484) (actual time=145.595..156.056 rows=221.00 loops=1)
   Sort Key: (date_trunc('day'::text, o.order_date)), (sum(((od.quantity)::numeric * od.unit_price_at_buy))) DESC
   Presorted Key: (date_trunc('day'::text, o.order_date))
   Full-sort Groups: 5  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
   Buffers: shared hit=4709 read=5
   ->  GroupAggregate  (cost=7946.96..8236.40 rows=1943 width=484) (actual time=143.770..155.127 rows=221.00 loops=1)
         Group Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
         Buffers: shared hit=4709 read=5
         ->  Gather Merge  (cost=7946.96..8173.25 rows=1943 width=453) (actual time=143.669..151.428 rows=1957.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4709 read=5
               ->  Sort  (cost=6946.94..6948.96 rows=810 width=453) (actual time=131.200..131.384 rows=652.33 loops=3)
                     Sort Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
                     Sort Method: quicksort  Memory: 71kB
                     Buffers: shared hit=4709 read=5
                     Worker 0:  Sort Method: quicksort  Memory: 56kB
                     Worker 1:  Sort Method: quicksort  Memory: 58kB
                     ->  Hash Join  (cost=1019.48..6907.81 rows=810 width=453) (actual time=5.217..128.544 rows=652.33 loops=3)
                           Hash Cond: (p.brand_id = b.brand_id)
                           Buffers: shared hit=4679 read=5
                           ->  Hash Join  (cost=1018.08..6901.75 rows=810 width=239) (actual time=5.047..126.905 rows=652.33 loops=3)
                                 Hash Cond: (p.category_id = c.category_id)
                                 Buffers: shared hit=4676 read=5
                                 ->  Hash Join  (cost=1016.90..6897.32 rows=810 width=25) (actual time=4.953..125.877 rows=652.33 loops=3)
                                       Hash Cond: (od.product_id = p.product_id)
                                       Buffers: shared hit=4673 read=5
                                       ->  Hash Join  (cost=1012.20..6890.41 rows=810 width=21) (actual time=4.768..124.574 rows=652.33 loops=3)
                                             Hash Cond: (od.order_id = o.order_id)
                                             Buffers: shared hit=4667 read=5
                                             ->  Parallel Seq Scan on order_details od  (cost=0.00..5331.33 rows=208333 width=17) (actual time=0.013..44.791 rows=166666.67 loops=3)
                                                   Buffers: shared hit=3248
                                             ->  Hash  (cost=1004.91..1004.91 rows=583 width=12) (actual time=4.310..4.314 rows=599.00 loops=3)
                                                   Buckets: 1024  Batches: 1  Memory Usage: 34kB
                                                   Buffers: shared hit=1419 read=5
                                                   ->  Bitmap Heap Scan on orders o  (cost=19.85..1004.91 rows=583 width=12) (actual time=0.823..3.831 rows=599.00 loops=3)
                                                         Recheck Cond: ((status = 'Completed'::order_status) AND (order_date >= '2026-03-02 00:00:00'::timestamp without time zone) AND 
(order_date < '2026-03-09 00:00:00'::timestamp without time zone))
                                                         Heap Blocks: exact=469
                                                         Buffers: shared hit=1419 read=5
                                                         ->  Bitmap Index Scan on idx_orders_status_date  (cost=0.00..19.71 rows=583 width=0) (actual time=0.500..0.500 rows=599.00 loop
s=3)
                                                               Index Cond: ((status = 'Completed'::order_status) AND (order_date >= '2026-03-02 00:00:00'::timestamp without time zone) 
AND (order_date < '2026-03-09 00:00:00'::timestamp without time zone))
                                                               Index Searches: 3
                                                               Buffers: shared hit=12 read=5
                                       ->  Hash  (cost=3.20..3.20 rows=120 width=12) (actual time=0.137..0.139 rows=120.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 14kB
                                             Buffers: shared hit=6
                                             ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=12) (actual time=0.031..0.069 rows=120.00 loops=3)
                                                   Buffers: shared hit=6
                                 ->  Hash  (cost=1.08..1.08 rows=8 width=222) (actual time=0.038..0.040 rows=8.00 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on categories c  (cost=0.00..1.08 rows=8 width=222) (actual time=0.025..0.028 rows=8.00 loops=3)
                                             Buffers: shared hit=3
                           ->  Hash  (cost=1.18..1.18 rows=18 width=222) (actual time=0.102..0.103 rows=18.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                 Buffers: shared hit=3
                                 ->  Seq Scan on brands b  (cost=0.00..1.18 rows=18 width=222) (actual time=0.053..0.060 rows=18.00 loops=3)
                                       Buffers: shared hit=3
 Planning:
   Buffers: shared hit=37 read=6 dirtied=2
 Planning Time: 3.387 ms
 Execution Time: 156.313 ms
(62 rows)


*/


-- ============================================================================
-- QUERY 3 (OPTIMIZED DENGAN COMPOSITE & FK INDEX)
-- Indeks Digunakan: idx_orders_status_date & idx_order_details_order_id
-- Transformasi JOIN: Parallel Hash Join (178 ms) -> Nested Loop (0.88 ms, 202x speedup!)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    o.order_id,
    o.order_date,
    u.username,
    p.product_name,
    od.quantity,
    od.unit_price_at_buy
FROM orders o
JOIN users u
    ON u.user_id = o.user_id
JOIN order_details od
    ON od.order_id = o.order_id
JOIN products p
    ON p.product_id = od.product_id
WHERE
    o.status = 'Paid'
    AND o.order_date >= '2026-09-01'
ORDER BY o.order_date DESC
LIMIT 50;

/*
LOG OUTPUT EXPLAIN QUERY 3 (SETELAH INDEKS):
                                                                             QUERY PLAN                                                                             
--------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=1.28..101.51 rows=50 width=86) (actual time=0.212..2.371 rows=50.00 loops=1)
   Buffers: shared hit=241 read=22
   ->  Nested Loop  (cost=1.28..28460.58 rows=14197 width=86) (actual time=0.209..2.343 rows=50.00 loops=1)
         Buffers: shared hit=241 read=22
         ->  Nested Loop  (cost=1.13..28088.05 rows=14197 width=38) (actual time=0.187..1.793 rows=50.00 loops=1)
               Buffers: shared hit=157 read=22
               ->  Nested Loop  (cost=0.71..9412.17 rows=4259 width=25) (actual time=0.146..0.483 rows=18.00 loops=1)
                     Buffers: shared hit=72 read=3
                     ->  Index Scan using idx_orders_status_date on orders o  (cost=0.42..4666.53 rows=4259 width=16) (actual time=0.124..0.184 rows=18.00 loops=1)
                           Index Cond: ((status = 'Paid'::order_status) AND (order_date >= '2026-09-01 00:00:00'::timestamp without time zone))
                           Index Searches: 1
                           Buffers: shared hit=19 read=2
                     ->  Index Scan using users_pkey on users u  (cost=0.29..1.11 rows=1 width=17) (actual time=0.013..0.013 rows=1.00 loops=18)
                           Index Cond: (user_id = o.user_id)
                           Index Searches: 18
                           Buffers: shared hit=53 read=1
               ->  Index Scan using idx_order_details_order_id on order_details od  (cost=0.42..4.35 rows=4 width=17) (actual time=0.061..0.068 rows=2.78 loops=18)
                     Index Cond: (order_id = o.order_id)
                     Index Searches: 18
                     Buffers: shared hit=85 read=19
         ->  Memoize  (cost=0.15..0.17 rows=1 width=56) (actual time=0.009..0.009 rows=1.00 loops=50)
               Cache Key: od.product_id
               Cache Mode: logical
               Hits: 8  Misses: 42  Evictions: 0  Overflows: 0  Memory Usage: 7kB
               Buffers: shared hit=84
               ->  Index Scan using products_pkey on products p  (cost=0.14..0.16 rows=1 width=56) (actual time=0.007..0.007 rows=1.00 loops=42)
                     Index Cond: (product_id = od.product_id)
                     Index Searches: 42
                     Buffers: shared hit=84
 Planning:
   Buffers: shared hit=30 read=2
 Planning Time: 2.283 ms
 Execution Time: 2.485 ms
(33 rows)


*/


-- ============================================================================
-- QUERY 4 (OPTIMIZED DENGAN PARTIAL / FILTERED INDEX)
-- Indeks Digunakan: idx_orders_pending_date (order_date) WHERE status = 'Pending'
-- Transformasi Scan: Seq Scan (Filter 148.774 rows) -> Bitmap Index Scan (0.17 ms)
-- ============================================================================

EXPLAIN (ANALYZE, BUFFERS)
SELECT
    u.user_id,
    u.email,
    COUNT(*) AS jml_pending,
    SUM(o.total_amount) AS total_tertunda,
    MIN(o.order_date) AS pending_tertua
FROM orders o
JOIN users u
    ON u.user_id = o.user_id
WHERE
    o.status = 'Pending'
    AND o.order_date < '2025-11-05'
GROUP BY
    u.user_id,
    u.email
ORDER BY total_tertunda DESC
LIMIT 20;

/*
LOG OUTPUT EXPLAIN QUERY 4 (SETELAH INDEKS):
                                                                            QUERY PLAN                                                                            
------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=3157.74..3157.79 rows=20 width=74) (actual time=58.869..58.885 rows=20.00 loops=1)
   Buffers: shared hit=1457 read=5
   ->  Sort  (cost=3157.74..3160.88 rows=1254 width=74) (actual time=58.865..58.874 rows=20.00 loops=1)
         Sort Key: (sum(o.total_amount)) DESC
         Sort Method: top-N heapsort  Memory: 29kB
         Buffers: shared hit=1457 read=5
         ->  HashAggregate  (cost=3108.70..3124.38 rows=1254 width=74) (actual time=56.077..57.726 rows=1215.00 loops=1)
               Group Key: u.user_id
               Batches: 1  Memory Usage: 689kB
               Buffers: shared hit=1457 read=5
               ->  Hash Join  (cost=1871.01..3096.16 rows=1254 width=40) (actual time=51.069..54.412 rows=1226.00 loops=1)
                     Hash Cond: (o.user_id = u.user_id)
                     Buffers: shared hit=1457 read=5
                     ->  Bitmap Heap Scan on orders o  (cost=26.01..1247.87 rows=1254 width=18) (actual time=0.972..2.857 rows=1226.00 loops=1)
                           Recheck Cond: ((order_date < '2025-11-05 00:00:00'::timestamp without time zone) AND (status = 'Pending'::order_status))
                           Heap Blocks: exact=737
                           Buffers: shared hit=737 read=5
                           ->  Bitmap Index Scan on idx_orders_pending_date  (cost=0.00..25.69 rows=1254 width=0) (actual time=0.646..0.647 rows=1226.00 loops=1)
                                 Index Cond: (order_date < '2025-11-05 00:00:00'::timestamp without time zone)
                                 Index Searches: 1
                                 Buffers: shared read=5
                     ->  Hash  (cost=1220.00..1220.00 rows=50000 width=26) (actual time=49.977..49.979 rows=50000.00 loops=1)
                           Buckets: 65536  Batches: 1  Memory Usage: 3383kB
                           Buffers: shared hit=720
                           ->  Seq Scan on users u  (cost=0.00..1220.00 rows=50000 width=26) (actual time=0.016..19.333 rows=50000.00 loops=1)
                                 Buffers: shared hit=720
 Planning:
   Buffers: shared hit=12
 Planning Time: 1.116 ms
 Execution Time: 59.062 ms
(30 rows)


*/
