-- Databricks notebook source
USE CATALOG churn_platform;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.customers AS
SELECT
  CAST(customer_id AS BIGINT)                         AS customer_id,
  TRIM(company_name)                                  AS company_name,
  TRIM(contact_name)                                  AS contact_name,
  LOWER(TRIM(email))                                  AS email,
  TRIM(industry)                                      AS industry,
  TRIM(company_size)                                  AS company_size,
  CAST(employee_count AS INT)                         AS employee_count,
  TRIM(plan_type)                                     AS plan_type,
  CAST(annual_contract_value AS DOUBLE)               AS annual_contract_value,
  TO_DATE(CAST(signup_date AS STRING))                AS signup_date,
  TRIM(region)                                        AS region,
  TRIM(country)                                       AS country,
  CAST(account_manager_id AS INT)                     AS account_manager_id,
  TRIM(payment_method)                                AS payment_method,
  CASE WHEN UPPER(TRIM(auto_renewal)) = 'YES' THEN 1 ELSE 0 END AS auto_renewal_flag,
  TO_DATE(CAST(contract_end_date AS STRING))          AS contract_end_date
FROM bronze.raw_customers
WHERE customer_id IS NOT NULL;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.churn_labels AS
SELECT
  CAST(customer_id AS BIGINT)                         AS customer_id,
  CASE WHEN UPPER(TRIM(churned)) = 'YES' THEN 1 ELSE 0 END AS is_churned,
  TO_DATE(CAST(churn_date AS STRING))                 AS churn_date,
  TRIM(churn_reason)                                  AS churn_reason,          
  CAST(churn_risk_score AS INT)                       AS leaky_churn_risk_score,
  CAST(tenure_months AS INT)                          AS leaky_tenure_months,    
  TRIM(latest_transaction_month)                      AS leaky_latest_txn_month,
  CASE WHEN UPPER(TRIM(has_recent_activity)) = 'YES' THEN 1 ELSE 0 END AS leaky_has_recent_activity
FROM bronze.raw_churn_labels
WHERE customer_id IS NOT NULL;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.transactions AS
SELECT
  CAST(transaction_id AS BIGINT)                      AS transaction_id,
  CAST(customer_id AS BIGINT)                         AS customer_id,
  COALESCE(TRY_TO_DATE(CAST(year_month AS STRING)),
           TRY_TO_DATE(CONCAT(CAST(year_month AS STRING), '-01'))) AS month_start,
  CAST(year AS INT)                                   AS year,
  CAST(month AS INT)                                  AS month,
  TRIM(quarter)                                       AS quarter,
  CAST(usage_hours AS DOUBLE)                         AS usage_hours,
  CAST(monthly_revenue AS DOUBLE)                     AS monthly_revenue,
  CAST(support_interactions AS INT)                   AS support_interactions,
  CAST(features_used AS INT)                          AS features_used,
  CAST(data_uploads_gb AS DOUBLE)                     AS data_uploads_gb,
  CAST(api_calls AS INT)                              AS api_calls
FROM bronze.raw_transactions
WHERE customer_id IS NOT NULL AND year_month IS NOT NULL;


-- COMMAND ----------

CREATE OR REPLACE TABLE silver.engagement AS
SELECT
  CAST(log_id AS BIGINT)                              AS log_id,
  CAST(customer_id AS BIGINT)                         AS customer_id,
  TO_DATE(CAST(log_date AS STRING))                   AS log_date,
  TRIM(feature_used)                                  AS feature_used,
  CAST(session_duration_minutes AS INT)               AS session_duration_minutes,
  CAST(actions_performed AS INT)                      AS actions_performed,
  TRIM(session_status)                                AS session_status,
  CASE WHEN session_status = 'Completed' THEN 1 ELSE 0 END AS is_completed,
  CASE WHEN session_status = 'Abandoned' THEN 1 ELSE 0 END AS is_abandoned,
  CASE WHEN session_status = 'Error'     THEN 1 ELSE 0 END AS is_error,
  TRIM(device_type)                                   AS device_type,
  TRIM(user_role)                                     AS user_role
FROM bronze.raw_engagement_logs
WHERE customer_id IS NOT NULL;

-- COMMAND ----------

CREATE OR REPLACE TABLE silver.tickets AS
SELECT
  CAST(ticket_id AS BIGINT)                           AS ticket_id,
  CAST(customer_id AS BIGINT)                         AS customer_id,
  TO_DATE(CAST(ticket_date AS STRING))                AS ticket_date,
  TRIM(ticket_type)                                   AS ticket_type,
  TRIM(severity)                                      AS severity,
  CASE TRIM(severity) WHEN 'Low' THEN 1 WHEN 'Medium' THEN 2
                      WHEN 'High' THEN 3 WHEN 'Critical' THEN 4 END AS severity_rank,
  TRIM(status)                                        AS status,
  CASE WHEN status IN ('Resolved','Closed') THEN 1 ELSE 0 END AS is_resolved,
  CAST(resolution_days AS DOUBLE)                     AS resolution_days,
  CAST(satisfaction_score AS DOUBLE)                  AS satisfaction_score,
  CASE WHEN UPPER(TRIM(escalated)) = 'YES' THEN 1 ELSE 0 END AS escalated_flag,
  CAST(agent_id AS INT)                               AS agent_id
FROM bronze.raw_support_tickets
WHERE customer_id IS NOT NULL;

-- COMMAND ----------

SELECT 'customers'    AS tbl, COUNT(*) AS n, 2000   AS expected FROM silver.customers     UNION ALL
SELECT 'churn_labels' ,       COUNT(*),      2000             FROM silver.churn_labels  UNION ALL
SELECT 'transactions' ,       COUNT(*),      79388            FROM silver.transactions  UNION ALL
SELECT 'engagement'   ,       COUNT(*),      244955           FROM silver.engagement    UNION ALL
SELECT 'tickets'      ,       COUNT(*),      19229            FROM silver.tickets;

-- COMMAND ----------

SELECT
  (SELECT COUNT(*) FROM silver.customers    WHERE signup_date IS NULL)        AS null_signup,
  (SELECT COUNT(*) FROM silver.customers    WHERE contract_end_date IS NULL)  AS null_contract_end,
  (SELECT COUNT(*) FROM silver.churn_labels WHERE is_churned = 1 AND churn_date IS NULL) AS churned_no_date,
  (SELECT COUNT(*) FROM silver.churn_labels WHERE is_churned = 0 AND churn_date IS NOT NULL) AS active_with_date,
  (SELECT COUNT(*) FROM silver.transactions WHERE month_start IS NULL)       AS null_month,
  (SELECT COUNT(*) FROM silver.engagement   WHERE log_date IS NULL)          AS null_log_date,
  (SELECT COUNT(*) FROM silver.tickets      WHERE ticket_date IS NULL)       AS null_ticket_date;

-- COMMAND ----------

SELECT SUM(is_churned) AS churned, COUNT(*) AS total, ROUND(100*AVG(is_churned),1) AS churn_pct
FROM silver.churn_labels;

-- COMMAND ----------

