-- =============================================================================
-- Project: Credit Portfolio Recovery Analytics
-- Script: 04_malla_analitica_consolidada.sql
-- Description: Master analytical query consolidating customer risk buckets, 
--              financial load ratios (Debt-to-Income), contactability tiers,
--              predictive scores, and recovery efficiency metrics.
-- Engine: PostgreSQL / Redshift / Yellowbrick SQL
-- =============================================================================

WITH master_analytical_mesh AS (
    SELECT 
        a.month_year,
        a.customer_id,
        a.risk_bucket,
        a.outstanding_balance,
        a.punctuality_score,
        a.native_directory_efficiency,
        a.monthly_income,
        
        -- 1. OPERATIONAL LEVER: Financial Load Ratio (Debt vs Income)
        ROUND((a.outstanding_balance / NULLIF(a.monthly_income, 0)) * 100, 2) AS financial_load_pct,
        CASE 
            WHEN (a.outstanding_balance * 1.0 / NULLIF(a.monthly_income, 0)) < 0.20 THEN '1. Low Load (<20%)'
            WHEN (a.outstanding_balance * 1.0 / NULLIF(a.monthly_income, 0)) BETWEEN 0.20 AND 0.50 THEN '2. Medium Load (20-50%)'
            ELSE '3. High Load (>50%)'
        END AS financial_load_tier,
        
        -- 2. DEMOGRAPHIC LEVER: Customer Age Bracket
        ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) AS customer_age,
        CASE 
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) < 25 THEN '1. < 25 years'
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) BETWEEN 25 AND 40 THEN '2. 25-40 years'
            WHEN ROUND(DATEDIFF(day, a.birth_date::DATE, a.record_date) / 365.25, 0) BETWEEN 41 AND 60 THEN '3. 41-60 years'
            ELSE '4. > 60 years'
        END AS age_bracket,
        
        -- 3. OPERATIONAL LEVER: Contactability Tiers from Predictive Model
        sc.contact_score,
        CASE 
            WHEN sc.contact_score >= 70 THEN '1. High Contactability (>=70 pts)'
            WHEN sc.contact_score BETWEEN 30 AND 69 THEN '2. Medium Contactability (30-69 pts)'
            ELSE '3. Low Contactability (<30 pts)'
        END AS contactability_tier,
        
        sc.payment_score,
        COALESCE(p.post_assignment_payments, 0) AS recovered_amount
    FROM (
        -- Base Portfolio Subquery
        SELECT * FROM (
            SELECT 
                customer_id / 10 AS customer_id,
                outstanding_balance,
                days_past_due,
                birth_date,
                punctuality_score,
                efficiency AS native_directory_efficiency,
                monthly_income,
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
    ) a
    -- Exclude Third-Party Managed Accounts
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
    -- Operational Predictive Scores
    LEFT JOIN (
        SELECT 
            customer_id,
            TO_CHAR(cutoff_date::DATE, 'YYYY-MM') AS month_year,
            contact_score,
            payment_score
        FROM analytics_db.stg_predictive_scores_history
        WHERE cutoff_date::DATE BETWEEN '2025-05-31' AND '2026-06-30'
    ) sc 
        ON a.customer_id = sc.customer_id 
       AND a.month_year = sc.month_year
    -- Real Recovered Payments
    LEFT JOIN (
        SELECT 
            customer_id,
            payment_date::DATE AS payment_date,
            TO_CHAR(payment_date::DATE, 'YYYY-MM') AS month_year,
            SUM(amount) AS post_assignment_payments
        FROM analytics_db.stg_daily_cash_payments 
        WHERE payment_type = 'ACCOUNT_CREDIT'
          AND payment_date BETWEEN '2025-06-01' AND '2026-06-30'
        GROUP BY 1, 2, 3
    ) p 
        ON a.customer_id = p.customer_id 
       AND a.month_year = p.month_year 
       AND p.payment_date >= a.record_date
    WHERE b.external_customer_id IS NULL
)

-- -----------------------------------------------------------------------------
-- IMPACT ANALYSIS OF OPERATIONAL VARIABLES ON REAL RECOVERY EFFICIENCY
-- -----------------------------------------------------------------------------
SELECT 
    risk_bucket,
    punctuality_score,
    age_bracket,
    contactability_tier,
    financial_load_tier,
    COUNT(DISTINCT customer_id) AS total_customers,
    AVG(monthly_income) AS avg_monthly_income,
    SUM(outstanding_balance) AS total_assigned_balance,
    SUM(recovered_amount) AS total_recovered_amount,
    ROUND((SUM(recovered_amount) / NULLIF(SUM(outstanding_balance), 0)) * 100, 2) AS real_efficiency_pct
FROM master_analytical_mesh
GROUP BY 
    risk_bucket, 
    punctuality_score, 
    age_bracket, 
    financial_load_tier, 
    contactability_tier
ORDER BY 
    risk_bucket ASC, 
    age_bracket ASC, 
    real_efficiency_pct DESC;
