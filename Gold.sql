-- Databricks notebook source
USE CATALOG churn_platform;

-- COMMAND ----------

CREATE OR REPLACE TABLE gold.customer_360 AS
WITH base AS (
  SELECT
    c.customer_id, c.industry, c.company_size, c.employee_count, c.plan_type,
    c.annual_contract_value, c.signup_date, c.region, c.country,
    c.account_manager_id, c.payment_method, c.auto_renewal_flag, c.contract_end_date,
    l.is_churned, l.churn_date, l.churn_reason,
    COALESCE(l.churn_date, DATE'2025-07-20') AS obs_date
  FROM silver.customers c
  JOIN silver.churn_labels l ON l.customer_id = c.customer_id
),
 

txn AS (
  SELECT
    b.customer_id,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.monthly_revenue END)       AS revenue_l3m,
    AVG(CASE WHEN t.month_start <  add_months(trunc(b.obs_date,'MM'),-3) THEN t.monthly_revenue END)       AS revenue_p3m,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.usage_hours END)           AS usage_hours_l3m,
    AVG(CASE WHEN t.month_start <  add_months(trunc(b.obs_date,'MM'),-3) THEN t.usage_hours END)           AS usage_hours_p3m,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.api_calls END)             AS api_calls_l3m,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.features_used END)         AS features_used_l3m,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.data_uploads_gb END)       AS data_uploads_gb_l3m,
    AVG(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN t.support_interactions END)  AS support_interactions_l3m,
    COUNT(CASE WHEN t.month_start >= add_months(trunc(b.obs_date,'MM'),-3) THEN 1 END)                     AS active_months_l3m
  FROM base b
  JOIN silver.transactions t
    ON  t.customer_id = b.customer_id
    AND t.month_start >= add_months(trunc(b.obs_date,'MM'),-6)
    AND t.month_start <  trunc(b.obs_date,'MM')
  GROUP BY b.customer_id
),
 

eng AS (
  SELECT
    b.customer_id,
    COUNT(CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN 1 END)                         AS sessions_l90,
    COUNT(CASE WHEN e.log_date <  date_sub(b.obs_date,90) THEN 1 END)                         AS sessions_p90,
    COUNT(DISTINCT CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.log_date END)       AS active_days_l90,
    AVG(CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.session_duration_minutes END)  AS avg_session_min_l90,
    AVG(CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.actions_performed END)         AS avg_actions_l90,
    AVG(CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.is_error END)                  AS error_rate_l90,
    AVG(CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.is_abandoned END)              AS abandon_rate_l90,
    COUNT(DISTINCT CASE WHEN e.log_date >= date_sub(b.obs_date,90) THEN e.feature_used END)   AS distinct_features_l90,
    datediff(MAX(b.obs_date), MAX(e.log_date))                                                AS days_since_last_session
  FROM base b
  JOIN silver.engagement e
    ON  e.customer_id = b.customer_id
    AND e.log_date >= date_sub(b.obs_date,180)
    AND e.log_date <  b.obs_date
  GROUP BY b.customer_id
),
 

tix AS (
  SELECT
    b.customer_id,
    COUNT(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) THEN 1 END)                              AS tickets_l90,
    COUNT(CASE WHEN k.ticket_date <  date_sub(b.obs_date,90) THEN 1 END)                              AS tickets_p90,
    COUNT(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) AND k.severity_rank >= 3 THEN 1 END)     AS high_sev_tickets_l90,
    SUM(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) THEN k.escalated_flag ELSE 0 END)          AS escalated_tickets_l90,
    COUNT(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) AND k.is_resolved = 0 THEN 1 END)        AS unresolved_tickets_l90,
    AVG(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) THEN k.satisfaction_score END)             AS avg_csat_l90,
    AVG(CASE WHEN k.ticket_date >= date_sub(b.obs_date,90) THEN k.resolution_days END)                AS avg_resolution_days_l90
  FROM base b
  JOIN silver.tickets k
    ON  k.customer_id = b.customer_id
    AND k.ticket_date >= date_sub(b.obs_date,180)
    AND k.ticket_date <  b.obs_date
  GROUP BY b.customer_id
)
 
SELECT
  
  b.customer_id,
  b.is_churned,                                   
  b.churn_date,                                  
  b.churn_reason,                                 
  b.obs_date,
 

  b.industry, b.company_size, b.employee_count, b.plan_type, b.region, b.country,
  b.payment_method, b.auto_renewal_flag, b.account_manager_id, b.annual_contract_value,
  CAST(months_between(b.obs_date, b.signup_date) AS INT)  AS tenure_months_at_obs,
  datediff(b.contract_end_date, b.obs_date)               AS days_to_contract_end,
 
  
  COALESCE(t.revenue_l3m, 0)               AS revenue_l3m,
  COALESCE(t.usage_hours_l3m, 0)           AS usage_hours_l3m,
  COALESCE(t.api_calls_l3m, 0)             AS api_calls_l3m,
  COALESCE(t.features_used_l3m, 0)         AS features_used_l3m,
  COALESCE(t.data_uploads_gb_l3m, 0)       AS data_uploads_gb_l3m,
  COALESCE(t.support_interactions_l3m, 0)  AS support_interactions_l3m,
  COALESCE(t.active_months_l3m, 0)         AS active_months_l3m,
  (t.revenue_l3m - t.revenue_p3m)         / NULLIF(t.revenue_p3m, 0)     AS revenue_change_pct,
  (t.usage_hours_l3m - t.usage_hours_p3m) / NULLIF(t.usage_hours_p3m, 0) AS usage_change_pct,
 

  COALESCE(e.sessions_l90, 0)              AS sessions_l90,
  COALESCE(e.sessions_p90, 0)              AS sessions_p90,
  (e.sessions_l90 - e.sessions_p90)       / NULLIF(e.sessions_p90, 0)    AS sessions_change_pct,
  COALESCE(e.active_days_l90, 0)           AS active_days_l90,
  e.avg_session_min_l90,
  e.avg_actions_l90,
  COALESCE(e.error_rate_l90, 0)            AS error_rate_l90,
  COALESCE(e.abandon_rate_l90, 0)          AS abandon_rate_l90,
  COALESCE(e.distinct_features_l90, 0)     AS distinct_features_l90,
  e.days_since_last_session,
 
 
  COALESCE(k.tickets_l90, 0)               AS tickets_l90,
  COALESCE(k.tickets_p90, 0)               AS tickets_p90,
  COALESCE(k.high_sev_tickets_l90, 0)      AS high_sev_tickets_l90,
  COALESCE(k.escalated_tickets_l90, 0)     AS escalated_tickets_l90,
  COALESCE(k.unresolved_tickets_l90, 0)    AS unresolved_tickets_l90,
  k.avg_csat_l90,
  k.avg_resolution_days_l90
 
FROM base b
LEFT JOIN txn t ON t.customer_id = b.customer_id
LEFT JOIN eng e ON e.customer_id = b.customer_id
LEFT JOIN tix k ON k.customer_id = b.customer_id;

-- COMMAND ----------

SELECT COUNT(*) AS rows_, COUNT(DISTINCT customer_id) AS customers,
       SUM(is_churned) AS churned, ROUND(100*AVG(is_churned),1) AS churn_pct
FROM gold.customer_360;
 


-- COMMAND ----------

SELECT
  SUM(CASE WHEN revenue_l3m = 0 THEN 1 ELSE 0 END)           AS no_txn_in_window,
  SUM(CASE WHEN sessions_l90 = 0 THEN 1 ELSE 0 END)          AS no_sessions_in_window,
  SUM(CASE WHEN avg_csat_l90 IS NULL THEN 1 ELSE 0 END)      AS no_csat_in_window
FROM gold.customer_360;

-- COMMAND ----------

SELECT is_churned,
       ROUND(AVG(revenue_l3m),0)          AS avg_revenue,
       ROUND(AVG(usage_hours_l3m),1)      AS avg_usage_hrs,
       ROUND(AVG(sessions_l90),1)         AS avg_sessions,
       ROUND(AVG(tickets_l90),2)          AS avg_tickets,
       ROUND(AVG(avg_csat_l90),2)         AS avg_csat,
       ROUND(AVG(tenure_months_at_obs),1) AS avg_tenure
FROM gold.customer_360
GROUP BY is_churned;

-- COMMAND ----------

