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
 Limit  (cost=3410.36..3410.37 rows=3 width=57) (actual time=39.185..39.202 rows=10.00 loops=1)
   Buffers: shared hit=1156 read=2
   ->  Sort  (cost=3410.36..3410.37 rows=3 width=57) (actual time=39.181..39.189 rows=10.00 loops=1)
         Sort Key: o.order_date DESC
         Sort Method: quicksort  Memory: 26kB
         Buffers: shared hit=1156 read=2
         ->  Nested Loop  (cost=0.29..3410.34 rows=3 width=57) (actual time=3.008..39.100 rows=10.00 loops=1)
               Buffers: shared hit=1153 read=2
               ->  Index Scan using users_pkey on users u  (cost=0.29..8.31 rows=1 width=39) (actual time=0.181..0.192 rows=1.00 loops=1)
                     Index Cond: (user_id = 38741)
                     Index Searches: 1
                     Buffers: shared hit=1 read=2
               ->  Seq Scan on orders o  (cost=0.00..3402.00 rows=3 width=26) (actual time=2.817..38.855 rows=10.00 loops=1)
                     Filter: ((order_date >= '2026-01-01 00:00:00'::timestamp without time zone) AND (user_id = 38741))
                     Rows Removed by Filter: 149990
                     Buffers: shared hit=1152
 Planning:
   Buffers: shared hit=97 dirtied=4
 Planning Time: 1.404 ms
 Execution Time: 39.310 ms
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
                                                             
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
-------------------------------------------------------------
 Incremental Sort  (cost=9635.69..9977.43 rows=1943 width=484) (actual time=151.189..159.834 rows=221.00 loops=1)
   Sort Key: (date_trunc('day'::text, o.order_date)), (sum(((od.quantity)::numeric * od.unit_price_at_buy))) DESC
   Presorted Key: (date_trunc('day'::text, o.order_date))
   Full-sort Groups: 5  Sort Method: quicksort  Average Memory: 28kB  Peak Memory: 28kB
   Buffers: shared hit=4445
   ->  GroupAggregate  (cost=9635.17..9924.61 rows=1943 width=484) (actual time=148.985..158.858 rows=221.00 loops=1)
         Group Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
         Buffers: shared hit=4442
         ->  Gather Merge  (cost=9635.17..9861.46 rows=1943 width=453) (actual time=148.916..155.294 rows=1957.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4442
               ->  Sort  (cost=8635.14..8637.17 rows=810 width=453) (actual time=137.520..137.698 rows=652.33 loops=3)
                     Sort Key: (date_trunc('day'::text, o.order_date)), c.category_name, b.brand_name
                     Sort Method: quicksort  Memory: 66kB
                     Buffers: shared hit=4442
                     Worker 0:  Sort Method: quicksort  Memory: 62kB
                     Worker 1:  Sort Method: quicksort  Memory: 57kB
                     ->  Hash Join  (cost=2707.69..8596.01 rows=810 width=453) (actual time=19.431..134.893 rows=652.33 loops=3)
                           Hash Cond: (p.brand_id = b.brand_id)
                           Buffers: shared hit=4412
                           ->  Hash Join  (cost=2706.29..8589.96 rows=810 width=239) (actual time=19.263..133.331 rows=652.33 loops=3)
                                 Hash Cond: (p.category_id = c.category_id)
                                 Buffers: shared hit=4409
                                 ->  Hash Join  (cost=2705.11..8585.53 rows=810 width=25) (actual time=19.157..132.349 rows=652.33 loops=3)
                                       Hash Cond: (od.product_id = p.product_id)
                                       Buffers: shared hit=4406
                                       ->  Parallel Hash Join  (cost=2700.41..8578.62 rows=810 width=21) (actual time=18.832..130.976 rows=652.33 loops=3)
                                             Hash Cond: (od.order_id = o.order_id)
                                             Buffers: shared hit=4400
                                             ->  Parallel Seq Scan on order_details od  (cost=0.00..5331.33 rows=208333 width=17) (actual time=0.024..42.021 rows=166666.67 loops=3)
                                                   Buffers: shared hit=3248
                                             ->  Parallel Hash  (cost=2696.12..2696.12 rows=343 width=12) (actual time=18.119..18.121 rows=199.67 loops=3)
                                                   Buckets: 1024  Batches: 1  Memory Usage: 104kB
                                                   Buffers: shared hit=1152
                                                   ->  Parallel Seq Scan on orders o  (cost=0.00..2696.12 rows=343 width=12) (actual time=0.073..17.729 rows=199.67 loops=3)
                                                         Filter: ((order_date >= '2026-03-02 00:00:00'::timestamp without time zone) AND (order_date < '2026-03-09 00:00:00'::timestamp 
without time zone) AND (status = 'Completed'::order_status))
                                                         Rows Removed by Filter: 49800
                                                         Buffers: shared hit=1152
                                       ->  Hash  (cost=3.20..3.20 rows=120 width=12) (actual time=0.227..0.228 rows=120.00 loops=3)
                                             Buckets: 1024  Batches: 1  Memory Usage: 14kB
                                             Buffers: shared hit=6
                                             ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=12) (actual time=0.042..0.112 rows=120.00 loops=3)
                                                   Buffers: shared hit=6
                                 ->  Hash  (cost=1.08..1.08 rows=8 width=222) (actual time=0.055..0.056 rows=8.00 loops=3)
                                       Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                       Buffers: shared hit=3
                                       ->  Seq Scan on categories c  (cost=0.00..1.08 rows=8 width=222) (actual time=0.024..0.029 rows=8.00 loops=3)
                                             Buffers: shared hit=3
                           ->  Hash  (cost=1.18..1.18 rows=18 width=222) (actual time=0.101..0.102 rows=18.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 9kB
                                 Buffers: shared hit=3
                                 ->  Seq Scan on brands b  (cost=0.00..1.18 rows=18 width=222) (actual time=0.054..0.063 rows=18.00 loops=3)
                                       Buffers: shared hit=3
 Planning:
   Buffers: shared hit=196 read=6
 Planning Time: 3.141 ms
 Execution Time: 160.125 ms
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
 Limit  (cost=9776.74..9799.88 rows=50 width=86) (actual time=173.669..187.295 rows=50.00 loops=1)
   Buffers: shared hit=4458 read=13
   ->  Nested Loop  (cost=9776.74..16348.53 rows=14197 width=86) (actual time=173.666..187.272 rows=50.00 loops=1)
         Buffers: shared hit=4458 read=13
         ->  Gather Merge  (cost=9776.44..11429.91 rows=14197 width=77) (actual time=173.501..186.144 rows=50.00 loops=1)
               Workers Planned: 2
               Workers Launched: 2
               Buffers: shared hit=4420
               ->  Sort  (cost=8776.41..8791.20 rows=5915 width=77) (actual time=161.577..161.771 rows=406.00 loops=3)
                     Sort Key: o.order_date DESC
                     Sort Method: quicksort  Memory: 649kB
                     Buffers: shared hit=4420
                     Worker 0:  Sort Method: quicksort  Memory: 642kB
                     Worker 1:  Sort Method: quicksort  Memory: 650kB
                     ->  Hash Join  (cost=2511.54..8405.83 rows=5915 width=77) (actual time=20.549..154.223 rows=4582.33 loops=3)
                           Hash Cond: (od.product_id = p.product_id)
                           Buffers: shared hit=4406
                           ->  Parallel Hash Join  (cost=2506.84..8385.06 rows=5915 width=29) (actual time=20.281..148.415 rows=4582.33 loops=3)
                                 Hash Cond: (od.order_id = o.order_id)
                                 Buffers: shared hit=4400
                                 ->  Parallel Seq Scan on order_details od  (cost=0.00..5331.33 rows=208333 width=17) (actual time=0.020..43.555 rows=166666.67 loops=3)
                                       Buffers: shared hit=3248
                                 ->  Parallel Hash  (cost=2475.53..2475.53 rows=2505 width=16) (actual time=19.650..19.652 rows=1376.00 loops=3)
                                       Buckets: 8192  Batches: 1  Memory Usage: 352kB
                                       Buffers: shared hit=1152
                                       ->  Parallel Seq Scan on orders o  (cost=0.00..2475.53 rows=2505 width=16) (actual time=0.045..17.988 rows=1376.00 loops=3)
                                             Filter: ((order_date >= '2026-09-01 00:00:00'::timestamp without time zone) AND (status = 'Paid'::order_status))
                                             Rows Removed by Filter: 48624
                                             Buffers: shared hit=1152
                           ->  Hash  (cost=3.20..3.20 rows=120 width=56) (actual time=0.218..0.219 rows=120.00 loops=3)
                                 Buckets: 1024  Batches: 1  Memory Usage: 19kB
                                 Buffers: shared hit=6
                                 ->  Seq Scan on products p  (cost=0.00..3.20 rows=120 width=56) (actual time=0.064..0.109 rows=120.00 loops=3)
                                       Buffers: shared hit=6
         ->  Memoize  (cost=0.30..1.12 rows=1 width=17) (actual time=0.021..0.021 rows=1.00 loops=50)
               Cache Key: o.user_id
               Cache Mode: logical
               Hits: 33  Misses: 17  Evictions: 0  Overflows: 0  Memory Usage: 2kB
               Buffers: shared hit=38 read=13
               ->  Index Scan using users_pkey on users u  (cost=0.29..1.11 rows=1 width=17) (actual time=0.050..0.050 rows=1.00 loops=17)
                     Index Cond: (user_id = o.user_id)
                     Index Searches: 17
                     Buffers: shared hit=38 read=13
 Planning:
   Buffers: shared hit=21 read=2
 Planning Time: 1.564 ms
 Execution Time: 187.431 ms
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
------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Limit  (cost=3229.79..3229.84 rows=20 width=74) (actual time=106.304..106.321 rows=20.00 loops=1)
   Buffers: shared hit=329 read=1118
   ->  Sort  (cost=3229.79..3232.90 rows=1242 width=74) (actual time=106.300..106.311 rows=20.00 loops=1)
         Sort Key: (sum(o.total_amount)) DESC
         Sort Method: top-N heapsort  Memory: 29kB
         Buffers: shared hit=329 read=1118
         ->  HashAggregate  (cost=3181.22..3196.74 rows=1242 width=74) (actual time=103.030..104.925 rows=1215.00 loops=1)
               Group Key: u.email
               Batches: 1  Memory Usage: 689kB
               Buffers: shared hit=329 read=1118
               ->  Hash Join  (cost=1855.91..3168.80 rows=1242 width=40) (actual time=70.955..97.976 rows=1226.00 loops=1)
                     Hash Cond: (o.user_id = u.user_id)
                     Buffers: shared hit=329 read=1118
                     ->  Bitmap Heap Scan on orders o  (cost=25.91..1335.54 rows=1242 width=18) (actual time=1.461..25.436 rows=1226.00 loops=1)
                           Recheck Cond: ((order_date < '2025-11-05 00:00:00'::timestamp without time zone) AND (status = 'Pending'::order_status))
                           Heap Blocks: exact=737
                           Buffers: shared hit=311 read=431
                           ->  Bitmap Index Scan on idx_orders_pending_date  (cost=0.00..25.60 rows=1242 width=0) (actual time=1.052..1.053 rows=1226.00 loops=1)
                                 Index Cond: (order_date < '2025-11-05 00:00:00'::timestamp without time zone)
                                 Index Searches: 1
                                 Buffers: shared read=5
                     ->  Hash  (cost=1205.00..1205.00 rows=50000 width=26) (actual time=68.352..68.355 rows=50000.00 loops=1)
                           Buckets: 65536  Batches: 1  Memory Usage: 3383kB
                           Buffers: shared hit=18 read=687
                           ->  Seq Scan on users u  (cost=0.00..1205.00 rows=50000 width=26) (actual time=0.665..27.492 rows=50000.00 loops=1)
                                 Buffers: shared hit=18 read=687
 Planning:
   Buffers: shared hit=17 read=1
 Planning Time: 1.084 ms
 Execution Time: 107.484 ms
(30 rows)


*/
