# Customer-Churn-Prediction-Retention-Analytics-Platform

An end-to-end customer churn analytics project built in **Databricks** using **Python, pandas, SQL, scikit-learn, and Power BI**.

The project combines customer profile, transaction, support, engagement, and churn-label data to identify customers at risk of leaving, explain the main churn drivers, and recommend targeted retention actions.

## Project Objective

The objective is to build a production-style churn analytics workflow that helps a SaaS business:

- Measure overall churn and retention performance
- Identify high-risk customers before they leave
- Understand the main behavioral and service-related churn drivers
- Compare churn patterns across plan, industry, and region
- Prioritize customer-retention actions
- Deliver business insights through a Power BI dashboard

This project was designed for the **Business Technology Solutions Associate – Gen AI** role at **ZS Associates**, with a strong focus on SQL, Python, Databricks, machine learning, Power BI, and business problem-solving.

## Technology Stack

| Area | Tools |
|---|---|
| Cloud analytics platform | Databricks |
| File storage | Unity Catalog Volumes |
| Data preparation | Python, pandas, NumPy |
| SQL analytics | Databricks SQL |
| Machine learning | scikit-learn |
| Visualization | Matplotlib, Seaborn |
| Dashboard | Power BI |
| Version control | GitHub |

> This project intentionally does **not** use PySpark. Python transformations are performed with pandas, while SQL is used for database-style feature engineering and analytics.

## Dataset Overview

The project uses five CSV datasets.

### 1. `customers_raw.csv`

Contains one row per customer, including company profile, plan, contract value, region, account manager, payment method, auto-renewal status, and contract dates.

Approximate rows: **2,000**

### 2. `transactions_raw.csv`

Contains monthly customer usage and revenue activity such as usage hours, monthly revenue, support interactions, feature usage, uploaded data, and API calls.

Approximate rows: **79,388**

### 3. `support_tickets_raw.csv`

Contains customer support requests, severity, status, resolution time, satisfaction score, escalation flag, and agent information.

Approximate rows: **19,229**

### 4. `engagement_logs_raw.csv`

Contains session behavior including feature used, session duration, actions performed, session status, device type, and user role.

Approximate rows: **244,955**

### 5. `churn_labels_raw.csv`

Contains churn outcome, churn date, churn reason, churn-risk score, tenure, latest activity month, and recent-activity flag.

Approximate rows: **2,000**

The churn rate is approximately **26%**.

## Business Churn Signals

The dataset includes realistic churn indicators such as:

- No recent transactions
- Declining product usage
- Low satisfaction scores
- High ticket volume
- Escalated support cases
- High session abandonment
- Low feature adoption
- `auto_renewal = No`

## Project Architecture

```text
Five CSV Files
      |
      v
Databricks Unity Catalog Volume
      |
      v
Python Data Preparation with pandas
      |
      v
Customer-Level Feature Engineering
      |
      +----------------------+
      |                      |
      v                      v
Databricks SQL          Python EDA
Feature Queries         and Visualization
      |                      |
      +----------+-----------+
                 |
                 v
Machine Learning
- Logistic Regression
- Random Forest
                 |
                 v
Churn Probability and Risk Segmentation
                 |
                 v
Retention Action Recommendations
                 |
                 v
Power BI Dashboard
```

## Databricks Project Structure

```text
Customer_Churn_Analytics/
│
├── 00_project_setup_sql
├── 01_python_data_preparation
├── 02_sql_feature_engineering
├── 03_python_eda_and_ml
└── 04_churn_scoring_and_outputs
```

Recommended Unity Catalog structure:

```text
Catalog: healthcare_dataset
Schema: customer_churn
Volume: data
```

Example file path:

```text
/Volumes/healthcare_dataset/customer_churn/data/customers_raw.csv
```

## End-to-End Workflow

### 1. Databricks Setup

- Create a dedicated Unity Catalog schema
- Create a managed volume
- Upload all five CSV datasets
- Verify file names and paths
- Organize notebooks by pipeline stage

### 2. Python Data Preparation

Using pandas:

- Load all five datasets
- Validate row and column counts
- Check missing values and duplicate records
- Convert date columns
- Standardize categorical values
- Validate data types
- Aggregate customer activity
- Merge all customer-level features

### 3. Customer Feature Engineering

The final modeling dataset contains one row per customer with features such as:

- `tenure_months`
- `recency_days`
- `frequency`
- `monetary`
- `avg_monthly_usage`
- `usage_trend`
- `total_support_tickets`
- `avg_satisfaction`
- `escalated_ticket_count`
- `avg_resolution_days`
- `total_engagement_sessions`
- `avg_session_duration`
- `abandonment_rate`
- `features_used_count`
- `auto_renewal_flag`
- `plan_type_encoded`

### 4. SQL Feature Engineering

Databricks SQL reproduces the customer-level features using:

- Aggregations
- Conditional aggregation
- Common Table Expressions
- Date functions
- Window functions
- Multi-table joins
- `CASE` statements

This demonstrates that the same business logic can be implemented in both Python and SQL.

### 5. Exploratory Data Analysis

The EDA section examines:

- Churn rate by plan type
- Churn rate by industry
- Churn rate by region
- Usage, satisfaction, and tenure distributions
- Churned versus retained customer comparisons
- Correlation between customer behavior and churn

### 6. Machine Learning

Two classification models are trained:

- **Logistic Regression** as an interpretable baseline
- **Random Forest** to capture nonlinear patterns and feature interactions

The data is split into:

```text
80% training data
20% testing data
```

Evaluation metrics:

- Accuracy
- Precision
- Recall
- F1-score
- ROC-AUC
- Confusion matrix

Because churn is a risk-detection problem, recall and ROC-AUC are especially important.

### 7. Churn Risk Scoring

The selected model generates a churn probability for every customer.

| Churn probability | Risk segment |
|---:|---|
| Above 70% | High Risk |
| 40%–70% | Medium Risk |
| Below 40% | Low Risk |

### 8. Retention Recommendations

| Condition | Recommended action |
|---|---|
| High Risk + Low Satisfaction | Immediate manager call + discount offer |
| High Risk + No Recent Activity | Re-engagement campaign + product demo |
| High Risk + Many Tickets | Dedicated support agent + issue resolution |
| Medium Risk + Declining Usage | Usage training webinar + feature highlight |
| Low Risk | Standard quarterly check-in |

## Power BI Dashboard

### Page 1: Executive Summary

- Total Customers
- Churn Rate
- At-Risk Count
- Average Contract Value
- Monthly churn trend
- Churn rate by plan type

### Page 2: Risk Segments

- High, Medium, and Low Risk distribution
- Top 20 at-risk customers
- Churn probability
- Recommended retention action
- Plan, region, and industry slicers

### Page 3: Churn Drivers

- Random Forest feature importance
- Churned versus retained comparison
- Usage, satisfaction, and support metrics
- Correlation heatmap

### Page 4: Support Quality Impact

- Satisfaction versus churn probability
- Churn rate by ticket severity
- Resolution-time trends
- Escalation impact

### Page 5: Retention Actions

- Risk segment by recommended action
- High-risk customer table
- Account-manager filter
- Action-priority matrix

## Core DAX Measures

```DAX
Total Customers =
COUNTROWS(customers)
```

```DAX
Churn Rate =
DIVIDE(
    CALCULATE(
        COUNTROWS(customers),
        customers[churned] = "Yes"
    ),
    COUNTROWS(customers),
    0
) * 100
```

```DAX
At Risk Count =
CALCULATE(
    COUNTROWS(customers),
    customers[risk_segment] = "High Risk"
)
```

```DAX
Avg Contract Value =
AVERAGE(customers[annual_contract_value])
```

```DAX
High Risk Churned =
CALCULATE(
    COUNTROWS(customers),
    customers[risk_segment] = "High Risk",
    customers[churned] = "Yes"
)
```

```DAX
Retention Rate =
100 - [Churn Rate]
```

## Key Business Questions Answered

- Which customers are most likely to churn?
- Which behavioral indicators are most strongly related to churn?
- Does declining usage increase churn risk?
- How does customer satisfaction affect churn?
- Are escalated tickets linked to higher churn?
- Which plans, regions, or industries require attention?
- Which customers should receive immediate intervention?
- What retention action should be assigned to each customer?

## Key Insights to Highlight

### 1. Declining engagement is an early churn signal

Customers with falling usage, fewer recent transactions, lower feature adoption, or high abandonment are more likely to churn.

### 2. Support quality materially affects retention

Low satisfaction, slow resolution, frequent tickets, and escalations are strong churn-risk indicators.

### 3. Churn prevention should be personalized

A customer with low satisfaction needs a different retention strategy from a customer who has simply stopped using the product. The project converts churn probabilities into specific recommended actions rather than producing model scores alone.

## Production Best Practices Demonstrated

- Dedicated Unity Catalog schema and volume
- Clear notebook separation
- Data-quality validation before modeling
- Customer-level modeling grain
- Reproducible feature definitions
- Separate training and test sets
- Comparison of interpretable and nonlinear models
- Business-oriented evaluation metrics
- Churn probability scoring
- Risk segmentation
- Actionable retention recommendations
- Power BI-ready output
- No unnecessary use of PySpark

## Interview Summary

> I built an end-to-end Customer Churn Prediction and Retention Analytics Platform in Databricks using pandas, SQL, scikit-learn, and Power BI. I integrated five customer datasets, created customer-level behavioral, revenue, support, and engagement features, and trained Logistic Regression and Random Forest models. I evaluated the models using precision, recall, F1-score, ROC-AUC, and confusion matrices. The selected model generated churn probabilities that were converted into High, Medium, and Low Risk segments with personalized retention actions. I then designed a five-page Power BI dashboard for executive reporting, churn-driver analysis, customer prioritization, and retention planning.

## Repository Structure

```text
customer-churn-retention-analytics/
│
├── data/
│   └── README.md
│
├── notebooks/
│   ├── 00_project_setup_sql.sql
│   ├── 01_python_data_preparation.py
│   ├── 02_sql_feature_engineering.sql
│   ├── 03_python_eda_and_ml.py
│   └── 04_churn_scoring_and_outputs.py
│
├── outputs/
│   ├── customer_features.csv
│   ├── customer_churn_scores.csv
│   └── feature_importance.csv
│
├── powerbi/
│   └── customer_churn_retention_dashboard.pbix
│
├── images/
│   └── dashboard_screenshots/
│
├── requirements.txt
└── README.md
```

## How to Run the Project

1. Create the Databricks schema and volume.
2. Upload the five source CSV files.
3. Run `00_project_setup_sql`.
4. Run `01_python_data_preparation`.
5. Run `02_sql_feature_engineering`.
6. Run `03_python_eda_and_ml`.
7. Run `04_churn_scoring_and_outputs`.
8. Export the final Power BI datasets.
9. Refresh the Power BI dashboard.


## Author

**Krishna Rathi**

Aspiring Data Analyst | SQL | Python | Power BI | Databricks | Machine Learning
