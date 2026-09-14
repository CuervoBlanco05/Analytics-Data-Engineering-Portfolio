-- =============================================================================
-- Historical Credit Collection Trends (12-Month Dynamic Pivot)
-- Author: Pablo Cárdenas Mendívil (CuervoBlanco)
-- Description: Aggregates historical monthly performance across Delinquency Buckets.
--              Pivots monthly KPIs into structured columns to feed executive dashboards.
-- Target Engine: PostgreSQL / Redshift
-- =============================================================================

WITH monthly_portfolio AS (
    SELECT 
        cliente / 10 AS idcte,
        vencido,
        CASE 
            WHEN moras = 0 THEN 1 
            WHEN moras < 7 THEN moras 
            ELSE 7 
        END AS bucket_mora,
        fechacarga::date AS fecha_asignacion,
        TO_CHAR(fechacarga::date, 'YYYY-MM') AS anio_mes,
        ROW_NUMBER() OVER (
            PARTITION BY cliente, LAST_DAY(fechacarga::date) 
            ORDER BY fechacarga::date ASC
        ) AS rn
    FROM core_banking.delinquency_portfolio
    WHERE cliente > 0 
      AND vencido > 0
      AND fechacarga::date BETWEEN '2025-06-01' AND '2026-06-30'
),

vendor_exclusions AS (
    SELECT DISTINCT 
        cliente_sindig,
        TO_CHAR(fechacarga::date, 'YYYY-MM') AS anio_mes
    FROM core_banking.third_party_vendor_assignments
    WHERE canal_cobranza IN (
        'IABOTCAT','IACATCLN','IACATMX','IADIRECT','IALABCLN',
        'IALABMX','IASIGA','IAVOICES','IAVOZY','SIGA','PENTAFON','SIGA_TES','TESTIGO'
    )
    AND fechacarga BETWEEN '2025-06-01' AND '2026-06-30'
),

agreements AS (
    SELECT DISTINCT 
        cliente / 10 AS idcte,
        TO_CHAR(horainicio::date, 'YYYY-MM') AS anio_mes
    FROM telephony_logs.call_center_movements
    WHERE horainicio::date BETWEEN '2025-06-01' AND '2026-06-30'
      AND cvemovimiento = 'T'
      AND tipomovimiento IN (1, 35, 39)
)

-- =============================================================================
-- MONTHLY AGREEMENT TRENDS BY DELINQUENCY BUCKET
-- =============================================================================
SELECT 
    p.bucket_mora,
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-06' THEN a.idcte END) AS "jun_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-07' THEN a.idcte END) AS "jul_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-08' THEN a.idcte END) AS "ago_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-09' THEN a.idcte END) AS "sep_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-10' THEN a.idcte END) AS "oct_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-11' THEN a.idcte END) AS "nov_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2025-12' THEN a.idcte END) AS "dic_2025",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-01' THEN a.idcte END) AS "ene_2026",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-02' THEN a.idcte END) AS "feb_2026",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-03' THEN a.idcte END) AS "mar_2026",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-04' THEN a.idcte END) AS "abr_2026",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-05' THEN a.idcte END) AS "may_2026",
    COUNT(DISTINCT CASE WHEN p.anio_mes = '2026-06' THEN a.idcte END) AS "jun_2026"
FROM monthly_portfolio p
LEFT JOIN vendor_exclusions v 
    ON p.idcte = v.cliente_sindig 
   AND p.anio_mes = v.anio_mes
INNER JOIN agreements a 
    ON p.idcte = a.idcte 
   AND p.anio_mes = a.anio_mes
WHERE p.rn = 1 
  AND v.cliente_sindig IS NULL
GROUP BY p.bucket_mora
ORDER BY p.bucket_mora ASC;
