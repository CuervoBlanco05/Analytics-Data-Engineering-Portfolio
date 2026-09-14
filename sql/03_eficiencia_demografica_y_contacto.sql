-- =============================================================================
-- Project: Credit Portfolio Recovery Analytics
-- Script: 03_eficiencia_demografica_y_contacto.sql
-- Description: Analyzes collection efficiency by cross-referencing customer 
--              demographics (age brackets), debt saturation, contact recency, 
--              and non-payment root causes.
-- Engine: PostgreSQL / Redshift / Yellowbrick SQL
-- =============================================================================

WITH base_portfolio AS (
    SELECT * FROM (
        SELECT 
            customer_id / 10 AS customer_id,
            debt_saturation_pct,
            outstanding_balance,
            days_past_due,
            birth_date,
            COALESCE(non_payment_reason_code, 0) AS non_payment_reason_code,
            last_contact_date,
            load_date::DATE AS record_date,
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
          AND outstanding_balance > 0
          AND load_date::DATE BETWEEN '2025-06-01' AND '2026-06-30'
    ) ax
    WHERE rn = 1
),

excluded_third_parties AS (
    SELECT DISTINCT 
        external_customer_id AS customer_id,
        TO_CHAR(load_date::DATE, 'YYYY-MM') AS month_year
    FROM analytics_db.stg_third_party_assignments
    WHERE channel_type IN ('VENDOR_A', 'VENDOR_B', 'PARTNER_EXTERNAL')
      AND load_date BETWEEN '2025-06-01' AND '2026-06-30'
),

grouped_payments AS (
    SELECT 
        p.customer_id,
        TO_CHAR(p.payment_date::DATE, 'YYYY-MM') AS month_year,
        SUM(p.amount) AS total_paid_amount
    FROM analytics_db.stg_daily_cash_payments p
    INNER JOIN base_portfolio bp 
        ON p.customer_id = bp.customer_id 
       AND TO_CHAR(p.payment_date::DATE, 'YYYY-MM') = bp.month_year
    WHERE p.payment_type = 'ACCOUNT_CREDIT' 
      AND p.payment_date BETWEEN '2025-06-01' AND '2026-06-30'
    GROUP BY p.customer_id, TO_CHAR(p.payment_date::DATE, 'YYYY-MM')
),

consolidated_mesh AS (
    SELECT 
        a.risk_bucket,
        a.non_payment_reason_code,
        
        -- Demographic Segmentation: Customer Age Calculation
        ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) AS customer_age,
        CASE 
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) < 25 THEN '1. < 25 years'
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) BETWEEN 25 AND 40 THEN '2. 25-40 years'
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) BETWEEN 41 AND 60 THEN '3. 41-60 years'
            ELSE '4. > 60 years'
        END AS age_bracket,

        -- Operational Metric: Debt Saturation Level
        CASE 
            WHEN a.debt_saturation_pct < 20 THEN 'Low Saturation (<20%)'
            WHEN a.debt_saturation_pct BETWEEN 20 AND 60 THEN 'Medium Saturation (20-60%)'
            ELSE 'High Saturation (>60%)'
        END AS saturation_range,

        -- Operational Metric: Contact Recency
        CASE 
            WHEN DATEDIFF(day, a.last_contact_date::DATE, a.record_date) <= 7 THEN 'Recent Contact (<=7 days)'
            WHEN DATEDIFF(day, a.last_contact_date::DATE, a.record_date) BETWEEN 8 AND 30 THEN 'Moderate Contact (8-30 days)'
            ELSE 'No Recent Contact (>30 days)'
        END AS contact_recency_range,

        a.outstanding_balance,
        COALESCE(p.total_paid_amount, 0) AS total_paid_amount
    FROM base_portfolio a
    LEFT JOIN excluded_third_parties b 
        ON a.customer_id = b.customer_id 
       AND a.mes = b.month_year
    LEFT JOIN grouped_payments p 
        ON a.customer_id = p.customer_id 
       AND a.mes = p.month_year
    WHERE b.customer_id IS NULL
)

-- -----------------------------------------------------------------------------
-- DEMOGRAPHIC & NON-PAYMENT CAUSE ANALYSIS
-- -----------------------------------------------------------------------------
SELECT 
    risk_bucket,
    non_payment_reason_code,
    age_bracket,
    saturation_range,
    contact_recency_range,
    COUNT(*) AS total_customers,
    AVG(customer_age) AS avg_group_age,
    SUM(outstanding_balance) AS total_assigned_balance,
    SUM(total_paid_amount) AS total_recovered_amount,
    ROUND((SUM(total_paid_amount) / NULLIF(SUM(outstanding_balance), 0)) * 100, 2) AS real_efficiency_pct
FROM consolidated_mesh
GROUP BY 
    risk_bucket, 
    non_payment_reason_code, 
    age_bracket, 
    saturation_range, 
    contact_recency_range
ORDER BY 
    risk_bucket ASC, 
    non_payment_reason_code ASC;
