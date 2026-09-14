-- =============================================================================
-- Demographic & Predictive Scoring Efficiency Analysis Mesh
-- Author: Pablo Cárdenas Mendívil (CuervoBlanco)
-- Description: Enriches credit portfolio with age buckets, predictive contact/payment
--              scores, and monthly income to evaluate native vs. actual recovery rate.
-- Target Engine: PostgreSQL / AWS Redshift
-- =============================================================================

WITH analytical_mesh AS (
    SELECT 
        a.idcte,
        a.mes,
        a.bucket_mora,
        a.vencido,
        a.puntualidad,
        a.eficiencia_directorio,
        a.ingresomensual,
        a.porcentvdo,
        
        -- Customer Age Calculation & Demographics Segmentation
        ROUND(DATEDIFF(day, a.fechanacimiento::date, a.fecha_asignacion) / 365.25, 0) AS edad_cliente,
        CASE
            WHEN ROUND(DATEDIFF(day, a.fechanacimiento::date, a.fecha_asignacion) / 365.25, 0) < 25 THEN '1. < 25 yrs'
            WHEN ROUND(DATEDIFF(day, a.fechanacimiento::date, a.fecha_asignacion) / 365.25, 0) BETWEEN 25 AND 40 THEN '2. 25-40 yrs'
            WHEN ROUND(DATEDIFF(day, a.fechanacimiento::date, a.fecha_asignacion) / 365.25, 0) BETWEEN 41 AND 60 THEN '3. 41-60 yrs'
            ELSE '4. > 60 yrs'
        END AS rango_edad,
        
        -- Predictive Scores
        c.score_contacto,
        c.score_convenio,
        c.score_pago,
        c.calif_pago_binario,
        
        COALESCE(d.pagos_post_asignacion, 0) AS monto_pagado

    FROM (
        SELECT 
            cliente / 10 AS idcte,
            vencido,
            moras,
            fechanacimiento,
            puntualidad, 
            eficiencia AS eficiencia_directorio,
            ingresomensual,
            porcentvdo,
            fechacarga::date AS fecha_asignacion,
            TO_CHAR(fechacarga::date, 'YYYY-MM') AS mes,
            CASE 
                WHEN moras = 0 THEN 1
                WHEN moras < 7 THEN moras
                ELSE 7 
            END AS bucket_mora,
            ROW_NUMBER() OVER(
                PARTITION BY cliente, LAST_DAY(fechacarga::date)
                ORDER BY fechacarga::date ASC 
            ) AS rn
        FROM core_banking.delinquency_portfolio
        WHERE cliente > 0 
          AND vencido > 0
          AND fechacarga::date BETWEEN '2026-06-01' AND '2026-06-30'
    ) a
    
    -- Exclude Third-Party Managed Accounts
    LEFT JOIN (
        SELECT DISTINCT 
            cliente_sindig,
            TO_CHAR(fechacarga::date, 'YYYY-MM') AS mes
        FROM core_banking.third_party_vendor_assignments
        WHERE canal_cobranza IN ('IABOTCAT','IACATCLN','IACATMX','IADIRECT','IALABCLN','IALABMX','IASIGA',
                                 'IAVOICES','IAVOZY','SIGA','PENTAFON','SIGA_TES','TESTIGO')
          AND fechacarga BETWEEN '2026-06-01' AND '2026-06-30'
    ) b ON a.idcte = b.cliente_sindig AND a.mes = b.mes
    
    -- Join Predictive Scores Catalog
    LEFT JOIN (
        SELECT
            idcte,
            TO_CHAR(fechacorte::date, 'YYYY-MM') AS mes,
            score_contacto,
            score_convenio,
            score_pago,
            calif_pago_binario
        from analytics_models.predictive_scoring_history
        WHERE fechacorte::date BETWEEN '2026-06-01' AND '2026-06-30'
    ) c ON a.idcte = c.idcte AND a.mes = c.mes
    
    -- Join Realized Customer Payments
    LEFT JOIN (
        SELECT
            idcte,
            fecha::date AS fecha_pagos,
            TO_CHAR(fecha::date, 'YYYY-MM') AS mes,
            SUM(importe) AS pagos_post_asignacion
        FROM financial_ledger.daily_customer_payments
        WHERE tipo_abono = 'CUENTA'
          AND fecha BETWEEN '2026-06-01' AND '2026-06-30'
        GROUP BY 1, 2, 3
    ) d ON a.idcte = d.idcte AND a.mes = d.mes AND d.fecha_pagos >= a.fecha_asignacion
    
    WHERE a.rn = 1 AND b.cliente_sindig IS NULL
)

-- =============================================================================
-- FINAL COMPARATIVE AGGREGATION: TARGET VS REALIZED EFFICIENCY
-- =============================================================================
SELECT
    bucket_mora,
    rango_edad,
    COUNT(DISTINCT idcte) AS total_clientes,
    ROUND(AVG(ingresomensual), 2) AS ingreso_promedio,
    ROUND(AVG(eficiencia_directorio), 2) AS eficiencia_teorica_pct,
    ROUND((SUM(monto_pagado) / NULLIF(SUM(vencido), 0)) * 100, 2) AS eficiencia_real_pct
FROM analytical_mesh
GROUP BY bucket_mora, rango_edad
ORDER BY bucket_mora ASC, rango_edad ASC;
