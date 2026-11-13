# Databricks notebook source
import numpy as np, pandas as pd
import matplotlib.pyplot as plt
from sklearn.model_selection import train_test_split, StratifiedKFold, cross_val_score, cross_val_predict
from sklearn.pipeline import Pipeline
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder, StandardScaler
from sklearn.impute import SimpleImputer
from sklearn.linear_model import LogisticRegression
from sklearn.ensemble import RandomForestClassifier, HistGradientBoostingClassifier
from sklearn.inspection import permutation_importance
from sklearn.metrics import (roc_auc_score, average_precision_score, roc_curve,
                             precision_recall_curve, confusion_matrix, classification_report)
 
SEED = 42
df = spark.table("churn_platform.gold.customer_360").toPandas()
print(df.shape, "| churn rate:", round(df.is_churned.mean(), 3))
 
NUM = ["annual_contract_value", "employee_count", "tenure_months_at_obs", "auto_renewal_flag",
       "revenue_l3m", "usage_hours_l3m", "api_calls_l3m", "features_used_l3m", "data_uploads_gb_l3m",
       "support_interactions_l3m", "active_months_l3m", "revenue_change_pct", "usage_change_pct",
       "sessions_l90", "sessions_change_pct", "active_days_l90", "avg_session_min_l90",
       "error_rate_l90", "abandon_rate_l90", "days_since_last_session",
       "tickets_l90", "high_sev_tickets_l90", "escalated_tickets_l90", "unresolved_tickets_l90",
       "avg_csat_l90", "avg_resolution_days_l90"]
CAT = ["industry", "company_size", "plan_type", "region", "payment_method"]
 
X = df[NUM + CAT].copy()
X[NUM] = X[NUM].astype(float).replace([np.inf, -np.inf], np.nan)   # pct-change can divide by 0
y = df.is_churned.astype(int)
 
Xtr, Xte, ytr, yte = train_test_split(X, y, test_size=0.2, stratify=y, random_state=SEED)
print("train", Xtr.shape, "test", Xte.shape)

# COMMAND ----------

def preprocessor(scale):
    num_steps = [("impute", SimpleImputer(strategy="median"))]
    if scale:
        num_steps.append(("scale", StandardScaler()))
    return ColumnTransformer([
        ("num", Pipeline(num_steps), NUM),
        ("cat", OneHotEncoder(handle_unknown="ignore"), CAT)])
 
models = {
    "Logistic Regression": Pipeline([("prep", preprocessor(True)),
        ("clf", LogisticRegression(max_iter=2000, C=0.5, class_weight="balanced"))]),
    "Random Forest": Pipeline([("prep", preprocessor(False)),
        ("clf", RandomForestClassifier(n_estimators=400, min_samples_leaf=5,
                                       class_weight="balanced_subsample", random_state=SEED, n_jobs=-1))]),
    "Gradient Boosting": Pipeline([("prep", preprocessor(False)),
        ("clf", HistGradientBoostingClassifier(max_depth=4, learning_rate=0.05, max_iter=300,
                                               l2_regularization=1.0, class_weight="balanced", random_state=SEED))]),
}

# COMMAND ----------

try:
    import mlflow, mlflow.sklearn
    mlflow.set_experiment(f"/Users/{spark.sql('select current_user()').first()[0]}/churn_prediction")
    USE_MLFLOW = True
except Exception as e:
    print("MLflow not available, continuing without it:", str(e)[:120]); USE_MLFLOW = False
 
def top_decile_stats(y_true, p):
    k = max(1, int(len(y_true) * 0.10))
    idx = np.argsort(-p)[:k]
    prec = y_true.values[idx].mean()
    return prec, prec / y_true.mean()
 
cv = StratifiedKFold(5, shuffle=True, random_state=SEED)
results, fitted = [], {}
for name, pipe in models.items():
    cv_auc = cross_val_score(pipe, Xtr, ytr, cv=cv, scoring="roc_auc").mean()
    pipe.fit(Xtr, ytr)
    p = pipe.predict_proba(Xte)[:, 1]
    prec10, lift10 = top_decile_stats(yte, p)
    m = {"cv_auc": cv_auc, "test_auc": roc_auc_score(yte, p),
         "test_pr_auc": average_precision_score(yte, p),
         "top10pct_precision": prec10, "top10pct_lift": lift10}
    results.append({"model": name, **m}); fitted[name] = pipe
    if USE_MLFLOW:
        try:
            with mlflow.start_run(run_name=name):
                mlflow.log_param("features", len(NUM) + len(CAT))
                mlflow.log_metrics({k: float(v) for k, v in m.items()})
                mlflow.sklearn.log_model(pipe, "model")
        except Exception as e:
            print("MLflow logging skipped for", name, "->", str(e)[:100])
 
res = pd.DataFrame(results).set_index("model").round(3)
display(res.reset_index())
best_name = res.cv_auc.idxmax()
print("Selected model (best cross-validated AUC):", best_name)
best = fitted[best_name]

# COMMAND ----------

p_te = best.predict_proba(Xte)[:, 1]
fig, axes = plt.subplots(1, 3, figsize=(17, 4.5))
 
fpr, tpr, _ = roc_curve(yte, p_te)
axes[0].plot(fpr, tpr, color="#2f6fdb"); axes[0].plot([0, 1], [0, 1], "k--", lw=1)
axes[0].set_title(f"ROC (AUC {roc_auc_score(yte, p_te):.3f})"); axes[0].set_xlabel("False positive rate"); axes[0].set_ylabel("True positive rate")
 
pr, rc, _ = precision_recall_curve(yte, p_te)
axes[1].plot(rc, pr, color="#2f6fdb"); axes[1].axhline(yte.mean(), color="k", ls="--", lw=1)
axes[1].set_title(f"Precision-Recall (AP {average_precision_score(yte, p_te):.3f})"); axes[1].set_xlabel("Recall"); axes[1].set_ylabel("Precision")
 
dec = pd.DataFrame({"y": yte.values, "p": p_te})
dec["decile"] = pd.qcut(dec.p.rank(method="first", ascending=False), 10, labels=range(1, 11))
dr = dec.groupby("decile", observed=True).y.mean() * 100
axes[2].bar(dr.index.astype(str), dr.values, color="#2f6fdb"); axes[2].axhline(yte.mean() * 100, color="red", ls="--", lw=1)
axes[2].set_title("Actual churn % by predicted-risk decile (1 = riskiest)"); axes[2].set_xlabel("Decile"); axes[2].set_ylabel("Churn %")
plt.tight_layout(); plt.show()

# COMMAND ----------

THRESH = 0.5
pred = (p_te >= THRESH).astype(int)
print("Confusion matrix at threshold", THRESH, "(rows = actual, cols = predicted)")
print(pd.DataFrame(confusion_matrix(yte, pred), index=["active", "churned"], columns=["pred active", "pred churned"]))
print(classification_report(yte, pred, target_names=["active", "churned"], digits=3))

# COMMAND ----------

pi = permutation_importance(best, Xte, yte, scoring="roc_auc", n_repeats=15, random_state=SEED, n_jobs=-1)
imp = (pd.DataFrame({"feature": Xte.columns, "auc_drop": pi.importances_mean, "std": pi.importances_std})
       .sort_values("auc_drop", ascending=False))
display(imp.head(15).round(4))
 
top = imp.head(12).iloc[::-1]
plt.figure(figsize=(8, 5))
plt.barh(top.feature, top.auc_drop, xerr=top["std"], color="#2f6fdb")
plt.title("Feature importance: AUC lost when the feature is shuffled"); plt.tight_layout(); plt.show()

# COMMAND ----------

oof = cross_val_predict(models[best_name], X, y, cv=cv, method="predict_proba")[:, 1]
 
pred_df = df[["customer_id", "is_churned", "plan_type", "industry", "region", "annual_contract_value"]].copy()
pred_df["churn_probability"] = oof.round(4)
pred_df["risk_rank_pct"] = pred_df.churn_probability.rank(pct=True, ascending=False).round(4)   # 0.01 = riskiest 1%
pred_df["risk_tier"] = np.select([pred_df.churn_probability >= 0.60, pred_df.churn_probability >= 0.40],
                                 ["High", "Medium"], default="Low")
pred_df["model_name"] = best_name

# COMMAND ----------

display(pred_df.groupby("risk_tier").agg(customers=("customer_id", "size"),
        actual_churn_pct=("is_churned", lambda s: round(100 * s.mean(), 1)),
        avg_probability=("churn_probability", "mean"),
        acv=("annual_contract_value", "sum")).round(2).reset_index())
 
(spark.createDataFrame(pred_df)
      .write.mode("overwrite").option("overwriteSchema", "true")
      .saveAsTable("churn_platform.gold.churn_predictions"))
print("Saved churn_platform.gold.churn_predictions:", len(pred_df), "rows")

# COMMAND ----------

