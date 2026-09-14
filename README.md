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
