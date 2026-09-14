-- =============================================================================
-- Project: Credit Portfolio Recovery Analytics
-- Script: 02_eficiencia_por_scores.sql
-- Description: Evaluates real collection efficiency (%) contrasting predictive
--              payment scores against risk buckets (days past due).
-- Engine: PostgreSQL / Redshift / Yellowbrick SQL
-- =============================================================================

WITH analytical_mesh AS (
    SELECT 
        a.month_year,
        a.customer_id,
        a.risk_bucket,
        a.outstanding_balance,
        
        -- Predictive Scores from Historical Scoring Engine
        sc.contact_score,
        sc.agreement_score,
        sc.payment_score,
        sc.general_score,
        sc.binary_payment_rank,
        
        -- Contact Management Flags
        COALESCE(mov.total_contacts, 0) AS total_contacts,
        CASE 
            WHEN mov.total_contacts > 0 THEN 1 
            ELSE 0 
        END AS is_contacted,
        
        -- Post-Assignment Recovered Amount
        COALESCE(p.post_assignment_payments, 0) AS recovered_amount
    FROM (
        -- Base Portfolio Selection
        SELECT * FROM (
            SELECT 
                customer_id / 10 AS customer_id,
                outstanding_balance,
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
    -- Predictive Scores Integration
    LEFT JOIN (
        SELECT 
            customer_id,
            TO_CHAR(cutoff_date::DATE, 'YYYY-MM') AS month_year,
            contact_score,
            agreement_score,
            payment_score,
            general_score,
            binary_payment_rank
        FROM analytics_db.stg_predictive_scores_history
        WHERE cutoff_date::DATE BETWEEN '2025-05-31' AND '2026-06-30'
    ) sc 
        ON a.customer_id = sc.customer_id 
       AND a.month_year = sc.month_year
    -- Collection Activity (Valid Calls)
    LEFT JOIN (
        SELECT 
            customer_id / 10 AS customer_id,
            TO_CHAR(start_time::DATE, 'YYYY-MM') AS month_year,
            COUNT(CASE WHEN interaction_code IN (1,2,3,4,5,9,6,7,22,25,30,34,35,39) THEN 1 END) AS total_contacts
        FROM (
            SELECT DISTINCT * 
            FROM analytics_db.stg_collection_interactions
        ) mov_a
        WHERE start_time::DATE BETWEEN '2025-06-01' AND '2026-06-30'
          AND interaction_type = 'TELEPHONE'
        GROUP BY 1, 2
    ) mov 
        ON a.customer_id = mov.customer_id 
       AND a.month_year = mov.month_year
    -- Actual Direct Payments
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
-- COMPARATIVE ANALYSIS: Predictive Score Rank vs Risk Bucket Performance
-- -----------------------------------------------------------------------------

-- GROUP 1: Grouped by Predictive Payment Score Rank
SELECT
    'By Predictive Score' AS analysis_type,
    'Score Tier ' || CAST(binary_payment_rank AS VARCHAR(50)) AS category,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(outstanding_balance) AS total_assigned_balance,
    SUM(recovered_amount) AS total_recovered_amount,
    ROUND((SUM(recovered_amount) / NULLIF(SUM(outstanding_balance), 0)) * 100, 2) AS efficiency_percentage
FROM analytical_mesh
GROUP BY 1, 2

UNION ALL

-- GROUP 2: Grouped by Risk Bucket (Moras)
SELECT 
    'By Risk Bucket' AS analysis_type,
    'Bucket ' || CAST(risk_bucket AS VARCHAR(50)) AS category,
    COUNT(DISTINCT customer_id) AS total_customers,
    SUM(outstanding_balance) AS total_assigned_balance,
    SUM(recovered_amount) AS total_recovered_amount,
    ROUND((SUM(recovered_amount) / NULLIF(SUM(outstanding_balance), 0)) * 100, 2) AS efficiency_percentage
FROM analytical_mesh
GROUP BY 1, 2

ORDER BY analysis_type, category;
