# Enterprise SQL Analytics: Credit Portfolio Recovery & Efficiency Pipelines

## Executive Overview
This repository contains production-ready SQL scripts designed to process, transform, and analyze large-scale credit portfolio data within enterprise Data Warehouses (PostgreSQL / Yellowbrick SQL). 

The primary objective of this pipeline architecture is to measure **Collection Efficiency (%)**, analyze customer contactability funnels, evaluate predictive scoring performance, and cross-reference demographic variables with financial debt capacity ratios.

## Repository Structure & Pipeline Architecture

```text
sql-data-transformation-portfolio/
├── README.md
└── sql/
    ├── 01_funnel_cobranza_historico.sql
    ├── 02_eficiencia_por_scores.sql
    ├── 03_eficiencia_demografica_y_contacto.sql
    └── 04_malla_analitica_consolidada.sql
```
---

## Executive BI & KPI Architecture

The production SQL pipelines in this repository are structured to feed executive-level Business Intelligence dashboards (Power BI / Tableau / Excel). The aggregation logic powers three core analytical modules:

1. **Monthly Portfolio Dynamic Pivots (Historical Rolling View):** 
   - Tracks 12-month rolling performance across 7 delinquency buckets.
   - Computes key operational KPIs: Total Assigned Portfolio, RPC Contact Rate, Agreement Conversion Rate, and Realized Recovery ($).

2. **Multidimensional Portfolio Efficiency Mesh:**
   - Cross-analyzes portfolio recovery performance against customer risk tiers (Punctuality Scores A–Z), age demographics (<25, 25–40, 41–60, >60 years), and financial exposure levels.
   - Compares theoretical baseline efficiency models against actual realized collection metrics.

3. **Call Center Movement Taxonomies:**
   - Standardizes raw telephony response codes (Movements 1 to 39) into executive outcome categories (Agreements, Refusals, Callbacks, Claims, and System Exclusions).
