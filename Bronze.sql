-- Databricks notebook source
CREATE CATALOG IF NOT EXISTS churn_platform;

-- COMMAND ----------

USE CATALOG churn_platform;

-- COMMAND ----------

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

-- COMMAND ----------

