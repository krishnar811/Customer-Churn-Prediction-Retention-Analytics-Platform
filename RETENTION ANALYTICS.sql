-- Databricks notebook source
USE CATALOG churn_platform;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.dashboard_customers AS
SELECT
  c.*,
  p.churn_probability,
  p.risk_tier,
  CASE WHEN c.is_churned = 1 THEN 'Churned' ELSE 'Active' END AS customer_status,
  CASE WHEN c.is_churned = 1 THEN date_trunc('quarter', c.churn_date) END AS churn_quarter,
  CASE WHEN c.auto_renewal_flag = 1 THEN 'Yes' ELSE 'No' END AS auto_renewal,
  CASE WHEN c.usage_change_pct <= -0.15 THEN 'Usage declining >15%'
       WHEN c.usage_change_pct IS NULL   THEN 'No prior usage'
       ELSE 'Stable or growing' END                          AS usage_trend
FROM gold.customer_360 c
JOIN gold.churn_predictions p ON p.customer_id = c.customer_id;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.kpi_summary AS
SELECT
  COUNT(*)                                                              AS total_customers,
  SUM(is_churned)                                                       AS churned_customers,
  ROUND(100.0 * AVG(is_churned), 1)                                     AS churn_rate_pct,
  ROUND(SUM(annual_contract_value), 0)                                  AS total_acv,
  ROUND(SUM(CASE WHEN is_churned = 1 THEN annual_contract_value END), 0) AS acv_lost,
  ROUND(100.0 * SUM(CASE WHEN is_churned = 1 THEN annual_contract_value END)
        / SUM(annual_contract_value), 1)                                AS acv_lost_pct,
  SUM(CASE WHEN is_churned = 0 AND risk_tier = 'High'   THEN 1 END)     AS active_high_risk,
  SUM(CASE WHEN is_churned = 0 AND risk_tier = 'Medium' THEN 1 END)     AS active_medium_risk,
  ROUND(SUM(CASE WHEN is_churned = 0 AND risk_tier IN ('High','Medium')
                 THEN annual_contract_value END), 0)                    AS acv_at_risk_high_medium,
  SUM(CASE WHEN is_churned = 0 AND usage_change_pct <= -0.15 THEN 1 END) AS active_usage_declining
FROM gold.dashboard_customers;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.churn_by_segment AS
WITH seg AS (
  SELECT 'Plan'           AS dimension, plan_type      AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Industry'       AS dimension, industry       AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Region'         AS dimension, region         AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Company size'   AS dimension, company_size   AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Payment cycle'  AS dimension, payment_method AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Auto-renewal'   AS dimension, auto_renewal   AS segment, * FROM gold.dashboard_customers UNION ALL
  SELECT 'Usage trend'    AS dimension, usage_trend    AS segment, * FROM gold.dashboard_customers
)
SELECT
  dimension, segment,
  COUNT(*)                                                       AS customers,
  SUM(is_churned)                                                AS churned,
  ROUND(100.0 * AVG(is_churned), 1)                              AS churn_rate_pct,
  ROUND(SUM(annual_contract_value), 0)                           AS total_acv,
  ROUND(SUM(CASE WHEN is_churned = 1 THEN annual_contract_value END), 0) AS acv_lost
FROM seg
GROUP BY dimension, segment;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.churn_trend_quarterly AS
SELECT
  churn_quarter,
  COUNT(*)                                  AS churned_customers,
  ROUND(SUM(annual_contract_value), 0)      AS acv_lost,
  ROUND(AVG(tenure_months_at_obs), 1)       AS avg_tenure_months
FROM gold.dashboard_customers
WHERE is_churned = 1
GROUP BY churn_quarter;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.churn_reasons AS
SELECT
  churn_reason, plan_type,
  COUNT(*)                              AS churned_customers,
  ROUND(SUM(annual_contract_value), 0)  AS acv_lost,
  ROUND(AVG(avg_csat_l90), 2)           AS avg_csat_before_churn,
  ROUND(AVG(tickets_l90), 2)            AS avg_tickets_l90
FROM gold.dashboard_customers
WHERE is_churned = 1
GROUP BY churn_reason, plan_type;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.retention_priority_list AS
SELECT
  customer_id, account_manager_id, plan_type, industry, region, company_size,
  annual_contract_value, risk_tier,
  ROUND(churn_probability, 3)                       AS churn_probability,
  ROUND(churn_probability * annual_contract_value, 0) AS priority_score,
  ROUND(100 * usage_change_pct, 1)                  AS usage_change_pct,
  support_interactions_l3m, tickets_l90, avg_csat_l90, avg_resolution_days_l90,
  auto_renewal,
  CASE
    WHEN avg_csat_l90 < 3 OR avg_resolution_days_l90 > 10 OR high_sev_tickets_l90 >= 2
         THEN 'Support recovery: exec/CSM call, fix open tickets'
    WHEN usage_change_pct <= -0.30
         THEN 'Urgent adoption rescue: usage collapsing, training and success plan'
    WHEN usage_change_pct <= -0.15
         THEN 'Adoption outreach: usage declining, schedule check-in'
    WHEN auto_renewal_flag = 0
         THEN 'Renewal conversation: auto-renew is off'
    ELSE 'Monitor: elevated model score'
  END                                               AS suggested_action,
  concat_ws(' | ',
    CASE WHEN usage_change_pct <= -0.15 THEN 'usage down' END,
    CASE WHEN support_interactions_l3m >= 4 THEN 'heavy support load' END,
    CASE WHEN avg_csat_l90 < 3 THEN 'low CSAT' END,
    CASE WHEN avg_resolution_days_l90 > 10 THEN 'slow resolutions' END,
    CASE WHEN auto_renewal_flag = 0 THEN 'no auto-renew' END
  )                                                 AS risk_signals,
  ROW_NUMBER() OVER (ORDER BY churn_probability * annual_contract_value DESC) AS priority_rank
FROM gold.dashboard_customers
WHERE is_churned = 0
  AND (risk_tier IN ('High','Medium') OR usage_change_pct <= -0.15);

-- COMMAND ----------

SELECT * FROM gold.kpi_summary;

-- COMMAND ----------


SELECT dimension, segment, customers, churn_rate_pct, acv_lost
FROM gold.churn_by_segment
ORDER BY dimension, churn_rate_pct DESC;
 
SELECT suggested_action, COUNT(*) AS customers, ROUND(SUM(annual_contract_value),0) AS acv
FROM gold.retention_priority_list
GROUP BY suggested_action ORDER BY customers DESC;
 
SELECT * FROM gold.retention_priority_list ORDER BY priority_rank LIMIT 20;

-- COMMAND ----------

