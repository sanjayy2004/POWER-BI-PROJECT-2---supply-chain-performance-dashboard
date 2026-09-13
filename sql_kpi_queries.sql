-- ============================================================
-- Supply Chain Performance Dashboard — KPI Queries
-- Run against the cleaned "gold" dataset loaded into SQL Server
-- as table: supply_chain_orders
-- ============================================================


-- ============================================================
-- 1. DATA VALIDATION
-- Confirms the SQL Server import matches the cleaned Python dataset
-- Expected: 180,519 rows, dates ranging 2015-01-01 to 2018-01-31
-- ============================================================

SELECT TOP 5 * FROM supply_chain_orders;

SELECT MIN([order date (DateOrders)]), MAX([order date (DateOrders)]) 
FROM supply_chain_orders;


-- ============================================================
-- 2. LATE DELIVERY RATE BY CATEGORY
-- Initial bottleneck check. Result: flat 55-62% across all ~50
-- categories — ruled out as a driver. The real signal is in
-- Shipping Mode (Section 3) instead.
-- ============================================================

SELECT 
    [Category Name],
    COUNT(*) AS total_orders,
    SUM(CASE WHEN [is_late] = 1 THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN [is_late] = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct,
    AVG(CAST([shipping_delay_days] AS FLOAT)) AS avg_delay_days
FROM supply_chain_orders
GROUP BY [Category Name]
ORDER BY late_pct DESC;


-- ============================================================
-- 3. LATE DELIVERY RATE BY SHIPPING MODE
-- Core finding: First Class = 100% late, zero variance.
-- This is the strongest single signal in the entire analysis.
-- ============================================================

SELECT 
    [Shipping Mode],
    COUNT(*) AS total_orders,
    SUM(CASE WHEN [is_late] = 1 THEN 1 ELSE 0 END) AS late_orders,
    ROUND(100.0 * SUM(CASE WHEN [is_late] = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct,
    AVG(CAST([shipping_delay_days] AS FLOAT)) AS avg_delay_days,
    AVG(CAST([Days for shipment (scheduled)] AS FLOAT)) AS avg_scheduled_days
FROM supply_chain_orders
GROUP BY [Shipping Mode]
ORDER BY late_pct DESC;


-- ============================================================
-- 4. FIRST CLASS — REGIONAL BREAKDOWN
-- Confirms the 100% late rate holds in all 23 regions, with no
-- exceptions — proving this is a structural SLA failure, not a
-- regional execution problem (Bottleneck #1).
-- ============================================================

SELECT 
    [Order Region],
    [Shipping Mode],
    COUNT(*) AS total_orders,
    ROUND(100.0 * SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct
FROM supply_chain_orders
WHERE [Shipping Mode] = 'First Class'
GROUP BY [Order Region], [Shipping Mode]
ORDER BY late_pct DESC;


-- ============================================================
-- 5. SECOND CLASS — REGIONAL BREAKDOWN
-- Real variance found (73-91%), unlike First Class. Western
-- Europe and Central America identified as the highest-volume,
-- highest-impact targets (Bottleneck #3).
-- ============================================================

SELECT 
    [Order Region],
    COUNT(*) AS total_orders,
    ROUND(100.0 * SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct
FROM supply_chain_orders
WHERE [Shipping Mode] = 'Second Class'
GROUP BY [Order Region]
ORDER BY late_pct DESC;


-- ============================================================
-- 6. PROFIT IMPACT: ON-TIME VS LATE (OVERALL)
-- Baseline profit erosion check across the whole dataset.
-- Result: ~4% erosion on late orders ($22.50 -> $21.59).
-- ============================================================

SELECT 
    is_late,
    COUNT(*) AS orders,
    AVG(CAST([Benefit per order] AS FLOAT)) AS avg_profit_per_order
FROM supply_chain_orders
GROUP BY is_late;


-- ============================================================
-- 7. PROFIT IMPACT: ON-TIME VS LATE, BY SHIPPING MODE
-- Reveals Same Day has the steepest erosion (-19.5%) when late —
-- roughly 4x worse than Standard Class (Bottleneck #2).
-- ============================================================

SELECT 
    [Shipping Mode],
    is_late,
    COUNT(*) AS orders,
    AVG(CAST([Benefit per order] AS FLOAT)) AS avg_profit_per_order
FROM supply_chain_orders
GROUP BY [Shipping Mode], is_late
ORDER BY [Shipping Mode], is_late;


-- ============================================================
-- 8. ORDER STATUS — LATE RATE & PROFIT
-- Tests fraud/cancellation as a possible driver of late delivery.
-- Result: ruled out — flat ~55.6-57.9% across every status,
-- including SUSPECTED_FRAUD and CANCELED.
-- ============================================================

SELECT 
    [Order Status],
    COUNT(*) AS total_orders,
    ROUND(100.0 * SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct,
    AVG(CAST([Benefit per order] AS FLOAT)) AS avg_profit_per_order
FROM supply_chain_orders
GROUP BY [Order Status]
ORDER BY total_orders DESC;


-- ============================================================
-- 9. YEAR-OVER-YEAR TREND
-- Tests whether the problem is worsening or improving over time.
-- Result: flat, stable ~57% every year (2015-2017) — confirms an
-- unaddressed, ongoing issue rather than a recent operational shift.
-- (2018 excluded from conclusions — partial year, only 2,123 orders)
-- ============================================================

SELECT 
    YEAR([order date (DateOrders)]) AS order_year,
    COUNT(*) AS total_orders,
    ROUND(100.0 * SUM(CASE WHEN is_late = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) AS late_pct,
    AVG(CAST(shipping_delay_days AS FLOAT)) AS avg_delay_days
FROM supply_chain_orders
GROUP BY YEAR([order date (DateOrders)])
ORDER BY order_year;
