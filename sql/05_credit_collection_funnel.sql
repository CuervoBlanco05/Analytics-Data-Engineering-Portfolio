-- =============================================================================
-- Executive Credit Portfolio Analytics: Collection Funnel Metrics by Bucket
-- Author: Pablo Cárdenas Mendívil (CuervoBlanco)
-- Description: End-to-end collection funnel aggregation. Segments active portfolio
--              by delinquency buckets, applies vendor exclusions, and computes 
--              funnel conversion stages.
-- Target Engine: PostgreSQL / AWS Redshift / ANSI SQL
-- =============================================================================

WITH 
-- 1. Base Portfolio Snapshot (First active assignment date of the month)
base_portfolio AS (
    SELECT 
        customer_id,
        overdue_balance,
        days_past_due,
        CASE 
            WHEN days_past_due = 0 THEN 1 
            WHEN days_past_due < 7 THEN days_past_due 
            ELSE 7 
        END AS bucket_mora,
        assignment_date::date AS fecha_asignacion,
        LAST_DAY(assignment_date::date) AS fecha_corte,
        ROW_NUMBER() OVER (
            PARTITION BY customer_id, LAST_DAY(assignment_date::date) 
            ORDER BY assignment_date::date ASC
        ) AS rn
    FROM core_banking.delinquency_portfolio
    WHERE customer_id > 0 
      AND overdue_balance > 0
      AND assignment_date::date BETWEEN '2026-06-01' AND '2026-06-30'
),

-- Filter only the first record per customer per month
filtered_portfolio AS (
    SELECT * 
    FROM base_portfolio 
    WHERE rn = 1
),

-- 2. Third-Party Vendor Exclusion List
excluded_vendors AS (
    SELECT DISTINCT customer_id
    FROM core_banking.third_party_vendor_assignments
    WHERE vendor_channel IN (
        'VENDOR_BOT_A','VENDOR_CAT_B','VENDOR_DIRECT','VENDOR_SIGA','VENDOR_TESTIGO'
    )
    AND assignment_date BETWEEN '2026-06-01' AND '2026-06-30'
),

-- 3. Telephony Movement Transactions (Deduplicated)
management_movements AS (
    SELECT DISTINCT 
        customer_id,
        movement_code,
        movement_type,
        agent_id,
        start_time::date AS fecha_gestion,
        LEAST(LAST_DAY(start_time::date), (start_time::date + (term_weeks * 7))) AS fecha_fin_convenio
    FROM telephony_logs.call_center_movements
    WHERE start_time::date BETWEEN '2026-06-01' AND '2026-06-30'
      AND movement_code = 'T'
),

-- 4. Daily Customer Payments
customer_payments AS (
    SELECT 
        customer_id,
        payment_date::date AS fecha_pago,
        SUM(amount) AS total_pagado
    FROM financial_ledger.daily_customer_payments
    WHERE payment_type = 'ACCOUNT_PAYMENT'
      AND payment_date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1, 2
),

-- 5. Financial Exposure (Exigible / Balance)
financial_exposure AS (
    SELECT 
        customer_id,
        overdue_balance,
        base_fee,
        current_balance,
        CASE 
            WHEN overdue_balance <= 0 THEN base_fee
            WHEN current_balance = overdue_balance THEN overdue_balance
            WHEN overdue_balance > 0 THEN LEAST(overdue_balance + base_fee, current_balance)
        END AS monto_exigible
    FROM financial_ledger.portfolio_financial_exposure
    WHERE snapshot_date::date = '2026-05-31'
)

-- =============================================================================
-- FINAL AGGREGATION: METRICS FUNNEL BY DELINQUENCY BUCKET (MORA)
-- =============================================================================
SELECT 
    p.bucket_mora AS mora_bucket,
    COUNT(DISTINCT p.customer_id) AS total_cartera_asignada,
    
    -- Coverage: Dialed / Ringing Calls (Exclude system movement 33)
    COUNT(DISTINCT CASE WHEN m.customer_id IS NOT NULL AND m.movement_type != 33 THEN p.customer_id END) AS clientes_llamada_enlazada,
    
    -- Coverage: Effective Contact (RPC)
    COUNT(DISTINCT CASE WHEN m.movement_type IN (1,2,3,4,5,6,7,9,22,25,30,34,35,39) THEN p.customer_id END) AS clientes_contacto_efectivo,
    
    -- Conversion: Payment Commitments (Agreements)
    COUNT(DISTINCT CASE WHEN m.movement_type IN (1,35,39) THEN p.customer_id END) AS clientes_con_convenio,
    
    -- Fulfillment: Kept Promises / Payments
    COUNT(DISTINCT CASE WHEN pay.fecha_pago >= p.fecha_asignacion THEN p.customer_id END) AS clientes_pagadores,
    
    -- Financial Impact: Total Exigible Portfolio Amount
    SUM(f.monto_exigible) AS exigible_total_monto

FROM filtered_portfolio p
LEFT JOIN excluded_vendors v ON p.customer_id = v.customer_id
LEFT JOIN management_movements m ON p.customer_id = m.customer_id
LEFT JOIN customer_payments pay ON p.customer_id = pay.customer_id
LEFT JOIN financial_exposure f ON p.customer_id = f.customer_id
WHERE v.customer_id IS NULL -- Apply third-party exclusion filter
GROUP BY 1
ORDER BY 1;
