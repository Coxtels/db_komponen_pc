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
LOG OUTPUT EXPLAIN QUERY 1 (SETELAH INDEKS):
                                                                   QUERY PLAN                                                                    
-------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=28.07..28.08 rows=3 width=57) (actual time=0.195..0.198 rows=10.00 loops=1)
   Buffers: shared hit=21
   ->  Sort  (cost=28.07..28.08 rows=3 width=57) (actual time=0.194..0.195 rows=10.00 loops=1)
         Sort Key: o.order_date DESC
         Sort Method: quicksort  Memory: 26kB
         Buffers: shared hit=21
         ->  Nested Loop  (cost=4.62..28.04 rows=3 width=57) (actual time=0.055..0.131 rows=10.00 loops=1)
               Buffers: shared hit=18
               ->  Index Scan using users_pkey on users u  (cost=0.29..8.31 rows=1 width=39) (actual time=0.020..0.021 rows=1.00 loops=1)
                     Index Cond: (user_id = 38741)
                     Index Searches: 1
                     Buffers: shared hit=3
               ->  Bitmap Heap Scan on orders o  (cost=4.33..19.71 rows=3 width=26) (actual time=0.033..0.105 rows=10.00 loops=1)
                     Recheck Cond: (user_id = 38741)
                     Filter: (order_date >= '2026-01-01 00:00:00'::timestamp without time zone)
                     Rows Removed by Filter: 3
                     Heap Blocks: exact=13
                     Buffers: shared hit=15
                     ->  Bitmap Index Scan on idx_orders_user_id  (cost=0.00..4.33 rows=4 width=0) (actual time=0.014..0.014 rows=13.00 loops=1)
                           Index Cond: (user_id = 38741)
                           Index Searches: 1
                           Buffers: shared hit=2
 Planning:
   Buffers: shared hit=223
 Planning Time: 0.845 ms
 Execution Time: 0.282 ms
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
---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Incremental Sort  (cost=7909.73..8239.84 rows=1877 width=63) (actual time=40.980..46.027 rows=221.00 loops=1)
   Sort Key: (date_trunc('day'::text, o.order_date)), (sum(((od.quantity)::numeric * od.unit_price_at_buy))) DESC
   Presorted Key: (date_trunc('day'::text, o.order_date))
   Full-sort Groups: 5  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
   Buffers: shared hit=4654
   ->  GroupAggregate  (cost=7909.21..8188.81 rows=1877 width=63) (actual time=40.380..45.722 rows=221.00 loops=1)
         Group Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
         Buffers: shared hit=4651
         ->  Gather Merge  (cost=7909.21..8127.81 rows=1877 width=32) (actual time=40.347..44.782 rows=1957.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4651
               ->  Sort  (cost=6909.18..6911.14 rows=782 width=32) (actual time=36.445..36.494 rows=652.33 loops=3)
                     Sort Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
                     Sort Method: quicksort  Memory: 68kB
                     Buffers: shared hit=4651
                     Worker 0:  Sort Method: quicksort  Memory: 58kB
                     Worker 1:  Sort Method: quicksort  Memory: 59kB
                     ->  Hash Join  (cost=1046.62..6871.60 rows=782 width=32) (actual time=1.730..35.774 rows=652.33 loops=3)
                           Hash Cond: (p.brand_id = b.brand_id)
                           Buffers: shared hit=4621
                           ->  Hash Join  (cost=1045.22..6865.71 rows=782 width=28) (actual time=1.671..35.388 rows=652.33 loops=3)
                                 Hash Cond: (p.category_id = c.category_id)
                                 Buffers: shared hit=4618
                                 ->  Hash Join  (cost=1044.04..6861.39 rows=782 width=25) (actual time=1.633..35.137 rows=652.33 loops=3)
                                       Hash Cond: (od.product_id = p.product_id)
                                       Buffers: shared hit=4615
                                       ->  Hash Join  (cost=1039.34..6854.56 rows=782 width=21) (actual time=1.558..34.782 rows=652.33 loops=3)
                                             Hash Cond: (od.order_id = o.order_id)
                                             Buffers: shared hit=4609
                                             ->  Parallel Seq Scan on order_details od  (cost=0.00..5268.33 rows=208333 width=17) (actual time=0.008..12.942 rows=166666.67 loops=3)
                                                   Buffers: shared hit=3185
                                             ->  Hash  (cost=1032.30..1032.30 rows=563 width=12) (actual time=1.453..1.455 rows=599.00 loops=3)
                                                   Buckets: 1024  Batches: 1  Memory Usage: 34kB
                                                   Buffers: shared hit=1424
                                                   ->  Bitmap Heap Scan on orders o  (cost=19.60..1032.30 rows=563 width=12) (actual time=0.262..1.338 rows=599.00 loops=3)
                                                         Recheck Cond: ((status = 'Completed'::order_status) AND (order_date >= '2026-03-02 00:00:00'::timestamp without time zone) AND (order_date < '2026-03-09 00:00:00'::timestamp without time zone))
                                                         Heap Blocks: exact=469
                                                         Buffers: shared hit=1424
                                                         ->  Bitmap Index Scan on idx_orders_status_date  (cost=0.00..19.46 rows=563 width=0) (actual time=0.172..0.172 rows=599.00 loops=3)
                                                               Index Cond: ((status = 'Completed'::order_status) AND (order_date >= '2026-03-02 00:00:00'::timestamp without time zone) AND (order_date < '2026-03-09 00:00:00'::timestamp without time zone))
                                                               Index Searches: 3
                                                               Buffers: shared hit=17
                                       ->  Hash  (cost=3.20..3.20 rows=120 width=12) (actual time=0.054..0.054 rows=120.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 14kB
                                             Buffers: shared hit=6
                                             ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=12) (actual time=0.010..0.025 rows=120.00 loops=3)
                                                   Buffers: shared hit=6
                                 ->  Hash  (cost=1.08..1.08 rows=8 width=11) (actual time=0.014..0.014 rows=8.00 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on categories c  (cost=0.00..1.08 rows=8 width=11) (actual time=0.008..0.009 rows=8.00 loops=3)
                                             Buffers: shared hit=3
                           ->  Hash  (cost=1.18..1.18 rows=18 width=12) (actual time=0.031..0.031 rows=18.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                 Buffers: shared hit=3
                                 ->  Seq Scan on brands b  (cost=0.00..1.18 rows=18 width=12) (actual time=0.017..0.019 rows=18.00 loops=3)
                                       Buffers: shared hit=3
 Planning:
   Buffers: shared hit=565
 Planning Time: 2.119 ms
 Execution Time: 46.280 ms
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
 Limit  (cost=1.28..102.25 rows=50 width=86) (actual time=0.108..0.917 rows=50.00 loops=1)
   Buffers: shared hit=263
   ->  Nested Loop  (cost=1.28..28492.20 rows=14110 width=86) (actual time=0.106..0.909 rows=50.00 loops=1)
         Buffers: shared hit=263
         ->  Nested Loop  (cost=1.13..28121.86 rows=14110 width=38) (actual time=0.078..0.754 rows=50.00 loops=1)
               Buffers: shared hit=179
               ->  Nested Loop  (cost=0.71..9711.94 rows=4233 width=25) (actual time=0.057..0.320 rows=18.00 loops=1)
                     Buffers: shared hit=75
                     ->  Index Scan using idx_orders_status_date on orders o  (cost=0.42..5034.29 rows=4233 width=16) (actual time=0.028..0.141 rows=18.00 loops=1)
                           Index Cond: ((status = 'Paid'::order_status) AND (order_date >= '2026-09-01 00:00:00'::timestamp without time zone))
                           Index Searches: 1
                           Buffers: shared hit=21
                     ->  Index Scan using users_pkey on users u  (cost=0.29..1.11 rows=1 width=17) (actual time=0.009..0.009 rows=1.00 loops=18)
                           Index Cond: (user_id = o.user_id)
                           Index Searches: 18
                           Buffers: shared hit=54
               ->  Index Scan using idx_order_details_order_id on order_details od  (cost=0.42..4.31 rows=4 width=17) (actual time=0.011..0.023 rows=2.78 loops=18)
                     Index Cond: (order_id = o.order_id)
                     Index Searches: 18
                     Buffers: shared hit=104
         ->  Memoize  (cost=0.15..0.17 rows=1 width=56) (actual time=0.003..0.003 rows=1.00 loops=50)
               Cache Key: od.product_id
               Cache Mode: logical
               Hits: 8  Misses: 42  Evictions: 0  Overflows: 0  Memory Usage: 7kB
               Buffers: shared hit=84
               ->  Index Scan using products_pkey on products p  (cost=0.14..0.16 rows=1 width=56) (actual time=0.002..0.002 rows=1.00 loops=42)
                     Index Cond: (product_id = od.product_id)
                     Index Searches: 42
                     Buffers: shared hit=84
 Planning:
   Buffers: shared hit=529 dirtied=1
 Planning Time: 2.118 ms
 Execution Time: 1.045 ms
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
 Limit  (cost=3229.79..3229.84 rows=20 width=74) (actual time=26.048..26.057 rows=20.00 loops=1)
   Buffers: shared hit=1450
   ->  Sort  (cost=3229.79..3232.90 rows=1242 width=74) (actual time=26.045..26.052 rows=20.00 loops=1)
         Sort Key: (sum(o.total_amount)) DESC
         Sort Method: top-N heapsort  Memory: 29kB
         Buffers: shared hit=1450
         ->  HashAggregate  (cost=3181.22..3196.74 rows=1242 width=74) (actual time=24.663..25.490 rows=1215.00 loops=1)
               Group Key: u.email
               Batches: 1  Memory Usage: 689kB
               Buffers: shared hit=1447
               ->  Hash Join  (cost=1855.91..3168.80 rows=1242 width=40) (actual time=21.076..23.447 rows=1226.00 loops=1)
                     Hash Cond: (o.user_id = u.user_id)
                     Buffers: shared hit=1447
                     ->  Bitmap Heap Scan on orders o  (cost=25.91..1335.54 rows=1242 width=18) (actual time=0.349..2.041 rows=1226.00 loops=1)
                           Recheck Cond: ((order_date < '2025-11-05 00:00:00'::timestamp without time zone) AND (status = 'Pending'::order_status))
                           Heap Blocks: exact=737
                           Buffers: shared hit=742
                           ->  Bitmap Index Scan on idx_orders_pending_date  (cost=0.00..25.60 rows=1242 width=0) (actual time=0.214..0.215 rows=1226.00 loops=1)
                                 Index Cond: (order_date < '2025-11-05 00:00:00'::timestamp without time zone)
                                 Index Searches: 1
                                 Buffers: shared hit=5
                     ->  Hash  (cost=1205.00..1205.00 rows=50000 width=26) (actual time=20.308..20.310 rows=50000.00 loops=1)
                           Buckets: 65536  Batches: 1  Memory Usage: 3383kB
                           Buffers: shared hit=705
                           ->  Seq Scan on users u  (cost=0.00..1205.00 rows=50000 width=26) (actual time=0.017..7.311 rows=50000.00 loops=1)
                                 Buffers: shared hit=705
 Planning:
   Buffers: shared hit=275
 Planning Time: 1.192 ms
 Execution Time: 26.410 ms
(30 rows)


*/
