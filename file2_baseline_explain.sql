-- ============================================================================
-- FILE 2: Script Query Baseline & Log Output EXPLAIN (ANALYZE, BUFFERS) Awal
-- Kasus: Basis Data Toko Komponen Komputer (db_komponen_pc)
-- RDBMS: PostgreSQL 18.6 (Arch Linux x86_64)
-- Kondisi: Baseline (Hanya Primary Key & Unique Constraint bawaan)
-- ============================================================================

-- ============================================================================
-- QUERY 1 (BASELINE)
-- Kasus: Riwayat pesanan satu pelanggan (o.user_id = 38741)
-- Target Optimasi: Single B-Tree Index (orders.user_id)
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
LOG OUTPUT EXPLAIN QUERY 1 (BASELINE):
                                                                QUERY PLAN                                                                
------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=3508.36..3508.37 rows=3 width=57) (actual time=17.647..17.653 rows=10.00 loops=1)
   Buffers: shared hit=1256
   ->  Sort  (cost=3508.36..3508.37 rows=3 width=57) (actual time=17.645..17.648 rows=10.00 loops=1)
         Sort Key: o.order_date DESC
         Sort Method: quicksort  Memory: 26kB
         Buffers: shared hit=1256
         ->  Nested Loop  (cost=0.29..3508.34 rows=3 width=57) (actual time=1.149..17.587 rows=10.00 loops=1)
               Buffers: shared hit=1253
               ->  Index Scan using users_pkey on users u  (cost=0.29..8.31 rows=1 width=39) (actual time=0.029..0.033 rows=1.00 loops=1)
                     Index Cond: (user_id = 38741)
                     Index Searches: 1
                     Buffers: shared hit=3
               ->  Seq Scan on orders o  (cost=0.00..3500.00 rows=3 width=26) (actual time=1.117..17.542 rows=10.00 loops=1)
                     Filter: ((order_date >= '2026-01-01 00:00:00'::timestamp without time zone) AND (user_id = 38741))
                     Rows Removed by Filter: 149990
                     Buffers: shared hit=1250
 Planning:
   Buffers: shared hit=159
 Planning Time: 0.748 ms
 Execution Time: 17.740 ms
(20 rows)


*/


-- ============================================================================
-- QUERY 2 (BASELINE)
-- Kasus: Laporan pendapatan harian per kategori dan merek (Rentang 02-09 Maret 2026)
-- Target Optimasi: Composite Index (orders.status, orders.order_date)
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
LOG OUTPUT EXPLAIN QUERY 2 (BASELINE):
                                                                                                                     QUERY PLAN                                                                                                                      
-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Incremental Sort  (cost=9668.65..9998.76 rows=1877 width=63) (actual time=120.640..129.503 rows=221.00 loops=1)
   Sort Key: (date_trunc('day'::text, o.order_date)), (sum(((od.quantity)::numeric * od.unit_price_at_buy))) DESC
   Presorted Key: (date_trunc('day'::text, o.order_date))
   Full-sort Groups: 5  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
   Buffers: shared hit=4480
   ->  GroupAggregate  (cost=9668.12..9947.73 rows=1877 width=63) (actual time=119.106..128.819 rows=221.00 loops=1)
         Group Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
         Buffers: shared hit=4477
         ->  Gather Merge  (cost=9668.12..9886.73 rows=1877 width=32) (actual time=119.040..126.508 rows=1957.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4477
               ->  Sort  (cost=8668.10..8670.05 rows=782 width=32) (actual time=109.741..109.856 rows=652.33 loops=3)
                     Sort Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
                     Sort Method: quicksort  Memory: 64kB
                     Buffers: shared hit=4477
                     Worker 0:  Sort Method: quicksort  Memory: 56kB
                     Worker 1:  Sort Method: quicksort  Memory: 65kB
                     ->  Hash Join  (cost=2805.54..8630.52 rows=782 width=32) (actual time=15.403..107.825 rows=652.33 loops=3)
                           Hash Cond: (p.brand_id = b.brand_id)
                           Buffers: shared hit=4447
                           ->  Hash Join  (cost=2804.14..8624.63 rows=782 width=28) (actual time=15.261..106.700 rows=652.33 loops=3)
                                 Hash Cond: (p.category_id = c.category_id)
                                 Buffers: shared hit=4444
                                 ->  Hash Join  (cost=2802.96..8620.30 rows=782 width=25) (actual time=15.151..105.972 rows=652.33 loops=3)
                                       Hash Cond: (od.product_id = p.product_id)
                                       Buffers: shared hit=4441
                                       ->  Parallel Hash Join  (cost=2798.26..8613.47 rows=782 width=21) (actual time=14.984..105.040 rows=652.33 loops=3)
                                             Hash Cond: (od.order_id = o.order_id)
                                             Buffers: shared hit=4435
                                             ->  Parallel Seq Scan on order_details od  (cost=0.00..5268.33 rows=208333 width=17) (actual time=0.033..33.718 rows=166666.67 loops=3)
                                                   Buffers: shared hit=3185
                                             ->  Parallel Hash  (cost=2794.12..2794.12 rows=331 width=12) (actual time=14.262..14.264 rows=199.67 loops=3)
                                                   Buckets: 1024  Batches: 1  Memory Usage: 104kB
                                                   Buffers: shared hit=1250
                                                   ->  Parallel Seq Scan on orders o  (cost=0.00..2794.12 rows=331 width=12) (actual time=0.044..13.968 rows=199.67 loops=3)
                                                         Filter: ((order_date >= '2026-03-02 00:00:00'::timestamp without time zone) AND (order_date < '2026-03-09 00:00:00'::timestamp without time zone) AND (status = 'Completed'::order_status))
                                                         Rows Removed by Filter: 49800
                                                         Buffers: shared hit=1250
                                       ->  Hash  (cost=3.20..3.20 rows=120 width=12) (actual time=0.119..0.120 rows=120.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 14kB
                                             Buffers: shared hit=6
                                             ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=12) (actual time=0.023..0.057 rows=120.00 loops=3)
                                                   Buffers: shared hit=6
                                 ->  Hash  (cost=1.08..1.08 rows=8 width=11) (actual time=0.047..0.048 rows=8.00 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on categories c  (cost=0.00..1.08 rows=8 width=11) (actual time=0.021..0.024 rows=8.00 loops=3)
                                             Buffers: shared hit=3
                           ->  Hash  (cost=1.18..1.18 rows=18 width=12) (actual time=0.083..0.084 rows=18.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                 Buffers: shared hit=3
                                 ->  Seq Scan on brands b  (cost=0.00..1.18 rows=18 width=12) (actual time=0.051..0.057 rows=18.00 loops=3)
                                       Buffers: shared hit=3
 Planning:
   Buffers: shared hit=485
 Planning Time: 4.256 ms
 Execution Time: 130.103 ms
(58 rows)


*/


-- ============================================================================
-- QUERY 3 (BASELINE)
-- Kasus: Feed 50 pesanan 'Paid' terbaru beserta item dan produknya (01 September 2026+)
-- Target Optimasi: Composite Index & Foreign Key Index (orders & order_details)
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
LOG OUTPUT EXPLAIN QUERY 3 (BASELINE):
                                                                               QUERY PLAN                                                                                
-------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=9808.94..9831.96 rows=50 width=86) (actual time=146.061..160.503 rows=50.00 loops=1)
   Buffers: shared hit=4506
   ->  Nested Loop  (cost=9808.94..16306.35 rows=14110 width=86) (actual time=146.058..160.471 rows=50.00 loops=1)
         Buffers: shared hit=4506
         ->  Gather Merge  (cost=9808.64..11451.98 rows=14110 width=77) (actual time=145.448..159.306 rows=50.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4455
               ->  Sort  (cost=8808.62..8823.31 rows=5879 width=77) (actual time=136.087..136.206 rows=404.67 loops=3)
                     Sort Key: o.order_date DESC
                     Sort Method: quicksort  Memory: 632kB
                     Buffers: shared hit=4455
                     Worker 0:  Sort Method: quicksort  Memory: 657kB
                     Worker 1:  Sort Method: quicksort  Memory: 652kB
                     ->  Hash Join  (cost=2609.35..8440.55 rows=5879 width=77) (actual time=17.897..129.702 rows=4582.33 loops=3)
                           Hash Cond: (od.product_id = p.product_id)
                           Buffers: shared hit=4441
                           ->  Parallel Hash Join  (cost=2604.65..8419.87 rows=5879 width=29) (actual time=17.640..125.486 rows=4582.33 loops=3)
                                 Hash Cond: (od.order_id = o.order_id)
                                 Buffers: shared hit=4435
                                 ->  Parallel Seq Scan on order_details od  (cost=0.00..5268.33 rows=208333 width=17) (actual time=0.026..37.499 rows=166666.67 loops=3)
                                       Buffers: shared hit=3185
                                 ->  Parallel Hash  (cost=2573.53..2573.53 rows=2490 width=16) (actual time=16.992..16.994 rows=1376.00 loops=3)
                                       Buckets: 8192  Batches: 1  Memory Usage: 352kB
                                       Buffers: shared hit=1250
                                       ->  Parallel Seq Scan on orders o  (cost=0.00..2573.53 rows=2490 width=16) (actual time=0.028..15.662 rows=1376.00 loops=3)
                                             Filter: ((order_date >= '2026-09-01 00:00:00'::timestamp without time zone) AND (status = 'Paid'::order_status))
                                             Rows Removed by Filter: 48624
                                             Buffers: shared hit=1250
                           ->  Hash  (cost=3.20..3.20 rows=120 width=56) (actual time=0.201..0.202 rows=120.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 19kB
                                 Buffers: shared hit=6
                                 ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=56) (actual time=0.056..0.096 rows=120.00 loops=3)
                                       Buffers: shared hit=6
         ->  Memoize  (cost=0.30..1.12 rows=1 width=17) (actual time=0.021..0.021 rows=1.00 loops=50)
               Cache Key: o.user_id
               Cache Mode: logical
               Hits: 33  Misses: 17  Evictions: 0  Overflows: 0  Memory Usage: 2kB
               Buffers: shared hit=51
               ->  Index Scan using users_pkey on users u  (cost=0.29..1.11 rows=1 width=17) (actual time=0.025..0.025 rows=1.00 loops=17)
                     Index Cond: (user_id = o.user_id)
                     Index Searches: 17
                     Buffers: shared hit=51
 Planning:
   Buffers: shared hit=443 dirtied=1
 Planning Time: 4.007 ms
 Execution Time: 161.232 ms
(47 rows)


*/


-- ============================================================================
-- QUERY 4 (BASELINE)
-- Kasus: Pesanan Pending tertunda dan total nominal per pelanggan (sebelum 05 Nov 2025)
-- Target Optimasi: Partial / Filtered Index pada orders(order_date) WHERE status = 'Pending'
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
LOG OUTPUT EXPLAIN QUERY 4 (BASELINE):
                                                                  QUERY PLAN                                                                  
----------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=5394.25..5394.30 rows=20 width=74) (actual time=45.537..45.546 rows=20.00 loops=1)
   Buffers: shared hit=1958
   ->  Sort  (cost=5394.25..5397.36 rows=1242 width=74) (actual time=45.534..45.541 rows=20.00 loops=1)
         Sort Key: (sum(o.total_amount)) DESC
         Sort Method: top-N heapsort  Memory: 29kB
         Buffers: shared hit=1958
         ->  HashAggregate  (cost=5345.68..5361.21 rows=1242 width=74) (actual time=44.554..45.097 rows=1215.00 loops=1)
               Group Key: u.email
               Batches: 1  Memory Usage: 689kB
               Buffers: shared hit=1955
               ->  Hash Join  (cost=1830.00..5333.26 rows=1242 width=40) (actual time=27.853..43.289 rows=1226.00 loops=1)
                     Hash Cond: (o.user_id = u.user_id)
                     Buffers: shared hit=1955
                     ->  Seq Scan on orders o  (cost=0.00..3500.00 rows=1242 width=18) (actual time=0.036..14.769 rows=1226.00 loops=1)
                           Filter: ((order_date < '2025-11-05 00:00:00'::timestamp without time zone) AND (status = 'Pending'::order_status))
                           Rows Removed by Filter: 148774
                           Buffers: shared hit=1250
                     ->  Hash  (cost=1205.00..1205.00 rows=50000 width=26) (actual time=27.025..27.029 rows=50000.00 loops=1)
                           Buckets: 65536  Batches: 1  Memory Usage: 3383kB
                           Buffers: shared hit=705
                           ->  Seq Scan on users u  (cost=0.00..1205.00 rows=50000 width=26) (actual time=0.034..9.453 rows=50000.00 loops=1)
                                 Buffers: shared hit=705
 Planning:
   Buffers: shared hit=193
 Planning Time: 1.388 ms
 Execution Time: 45.937 ms
(26 rows)


*/
