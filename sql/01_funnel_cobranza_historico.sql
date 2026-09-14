-- =============================================================================
-- Project: Credit Portfolio Recovery Analytics
-- Script: 01_funnel_cobranza_historico.sql
-- Description: Historical monthly funnel analysis for assigned portfolio,
--              contactability, payment agreements, and recovery metrics.
-- Engine: PostgreSQL / Redshift / Yellowbrick SQL
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. BASE PORTFOLIO: Total assigned clients grouped by bucket risk (Moras)
-- -----------------------------------------------------------------------------
WITH base_portfolio AS (
    SELECT 
        a.risk_bucket,
        COUNT(CASE WHEN a.month_year = '2025-06' THEN a.customer_id END) AS "2025-06",
        COUNT(CASE WHEN a.month_year = '2025-07' THEN a.customer_id END) AS "2025-07",
        COUNT(CASE WHEN a.month_year = '2025-08' THEN a.customer_id END) AS "2025-08",
        COUNT(CASE WHEN a.month_year = '2025-09' THEN a.customer_id END) AS "2025-09",
        COUNT(CASE WHEN a.month_year = '2025-10' THEN a.customer_id END) AS "2025-10",
        COUNT(CASE WHEN a.month_year = '2025-11' THEN a.customer_id END) AS "2025-11",
        COUNT(CASE WHEN a.month_year = '2025-12' THEN a.customer_id END) AS "2025-12",
        COUNT(CASE WHEN a.month_year = '2026-01' THEN a.customer_id END) AS "2026-01",
        COUNT(CASE WHEN a.month_year = '2026-02' THEN a.customer_id END) AS "2026-02",
        COUNT(CASE WHEN a.month_year = '2026-03' THEN a.customer_id END) AS "2026-03",
        COUNT(CASE WHEN a.month_year = '2026-04' THEN a.customer_id END) AS "2026-04",
        COUNT(CASE WHEN a.month_year = '2026-05' THEN a.customer_id END) AS "2026-05",
        COUNT(CASE WHEN a.month_year = '2026-06' THEN a.customer_id END) AS "2026-06"
    FROM (   
        SELECT 
            customer_id,
            TO_CHAR(load_date::DATE, 'YYYY-MM') AS month_year,
            CASE 
                WHEN days_past_due = 0 THEN 1
                WHEN days_past_due < 7 THEN days_past_due
                ELSE 7 
            END AS risk_bucket,
            ROW_NUMBER() OVER (
                PARTITION BY customer_id, LAST_DAY(load_date::DATE) 
                ORDER BY load_date::DATE ASC
            ) AS rn
        FROM analytics_db.stg_portfolio_directory
        WHERE customer_id > 0
          AND load_date::DATE BETWEEN '2025-06-01' AND '2026-06-30'
    ) a
    -- Exclude externalized third-party channels
    LEFT JOIN (
        SELECT DISTINCT 
            external_customer_id,
            TO_CHAR(load_date::DATE, 'YYYY-MM') AS month_year
        FROM analytics_db.stg_third_party_assignments
        WHERE channel_type IN ('VENDOR_A', 'VENDOR_B', 'PARTNER_EXTERNAL')
          AND load_date BETWEEN '2025-06-01' AND '2026-06-30'
    ) b
        ON a.customer_id = b.external_customer_id 
       AND a.month_year = b.month_year 
    WHERE a.rn = 1 
      AND b.external_customer_id IS NULL
    GROUP BY a.risk_bucket
)
SELECT * 
FROM base_portfolio
ORDER BY risk_bucket ASC;

-- -----------------------------------------------------------------------------
-- 2. COVERAGE METRIC: Customers with valid call interactions
-- -----------------------------------------------------------------------------
SELECT 
    a.month_year,
    a.risk_bucket,
    COUNT(DISTINCT a.customer_id) AS covered_customers
FROM (
    SELECT * FROM (
        SELECT 
            customer_id / 10 AS customer_id,
            outstanding_balance,
            days_past_due,
            TO_CHAR(load_date::DATE, 'YYYY-MM') AS month_year,
            CASE 
                WHEN days_past_due = 0 THEN 1 
                WHEN days_past_due < 7 THEN days_past_due 
                ELSE 7 
            END AS risk_bucket, 
            load_date::DATE AS record_date, 
            ROW_NUMBER() OVER (
                PARTITION BY customer_id, LAST_DAY(load_date::DATE) 
                ORDER BY load_date::DATE ASC
            ) AS rn
        FROM analytics_db.stg_portfolio_directory 
        WHERE customer_id > 0 
          AND outstanding_balance > 0
          AND load_date::DATE BETWEEN '2025-06-01' AND '2026-06-30'
    ) ax
    WHERE rn = 1
) a
LEFT JOIN (
    SELECT DISTINCT 
        external_customer_id,
        TO_CHAR(load_date::DATE, 'YYYY-MM') AS month_year
    FROM analytics_db.stg_third_party_assignments
    WHERE channel_type IN ('VENDOR_A', 'VENDOR_B', 'PARTNER_EXTERNAL')
      AND load_date BETWEEN '2025-06-01' AND '2026-06-30'
) b
    ON a.customer_id = b.external_customer_id 
   AND a.month_year = b.month_year
INNER JOIN (
    SELECT DISTINCT 
        customer_id / 10 AS customer_id,
        TO_CHAR(start_time::DATE, 'YYYY-MM') AS month_year
    FROM (
        SELECT DISTINCT * 
        FROM analytics_db.stg_collection_interactions
    ) mov_a
    WHERE start_time::DATE BETWEEN '2025-06-01' AND '2026-06-30'
      AND interaction_type = 'TELEPHONE'
) mov
    ON a.customer_id = mov.customer_id 
   AND a.month_year = mov.month_year
WHERE b.external_customer_id IS NULL 
GROUP BY 
    a.month_year,
    a.risk_bucket
ORDER BY 
    a.month_year ASC,
    a.risk_bucket ASC;
