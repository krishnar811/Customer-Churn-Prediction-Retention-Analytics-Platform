# Databricks notebook source
import pandas as pd, numpy as np
import matplotlib.pyplot as plt
from sklearn.metrics import roc_auc_score
 
plt.rcParams.update({"axes.grid": True, "grid.alpha": 0.3, "axes.spines.top": False, "axes.spines.right": False})
pdf = spark.table("churn_platform.gold.customer_360").toPandas()
print(pdf.shape, "| churned:", int(pdf.is_churned.sum()), f"({pdf.is_churned.mean():.1%})")

# COMMAND ----------

def churn_by(col, ax):
    s = pdf.groupby(col).is_churned.agg(["mean", "size"]).sort_values("mean", ascending=False)
    ax.barh(s.index.astype(str), s["mean"] * 100, color="#2f6fdb")
    ax.invert_yaxis()
    ax.axvline(pdf.is_churned.mean() * 100, color="red", ls="--", lw=1)
    ax.set_title(f"Churn % by {col}"); ax.set_xlabel("churn %"); ax.set_ylabel("")
 
fig, axes = plt.subplots(2, 3, figsize=(17, 8))
for ax, col in zip(axes.flat, ["plan_type", "industry", "company_size", "region", "payment_method", "auto_renewal_flag"]):
    churn_by(col, ax)
plt.tight_layout(); plt.show()  

# COMMAND ----------

ch = pdf[pdf.is_churned == 1].copy()
ch["churn_date"] = pd.to_datetime(ch.churn_date)
 
fig, axes = plt.subplots(1, 2, figsize=(16, 4.5))
ch.groupby(ch.churn_date.dt.to_period("Q")).size().plot(kind="bar", ax=axes[0], color="#2f6fdb")
axes[0].set_title("Churned customers per quarter"); axes[0].set_xlabel("")
ch.churn_reason.value_counts().sort_values().plot(kind="barh", ax=axes[1], color="#2f6fdb")
axes[1].set_title("Churn reasons (analysis only, not a model feature)")
plt.tight_layout(); plt.show()

# COMMAND ----------

acv = pdf.groupby("is_churned").annual_contract_value.sum()
print(f"ACV lost to churn: {acv[1]:,.0f} of {acv.sum():,.0f} ({acv[1]/acv.sum():.1%})")
print(pdf.groupby("plan_type").apply(lambda d: d.loc[d.is_churned == 1, "annual_contract_value"].sum()).round(0).sort_values(ascending=False))

# COMMAND ----------

num_cols = [c for c in pdf.select_dtypes("number").columns
            if c not in ("customer_id", "is_churned", "account_manager_id")]
rows = []
for c in num_cols:
    s = pdf[[c, "is_churned"]].dropna()
    if s.is_churned.nunique() == 2 and s[c].nunique() > 1:
        rows.append((c, roc_auc_score(s.is_churned, s[c]), s[s.is_churned == 1][c].mean(), s[s.is_churned == 0][c].mean(), len(s)))
auc = pd.DataFrame(rows, columns=["feature", "auc", "churned_mean", "active_mean", "n"])
auc["strength"] = (auc.auc - 0.5).abs()
auc = auc.sort_values("strength", ascending=False)
display(auc.drop(columns="strength").round(3))
 
top = auc.head(10).iloc[::-1]
plt.figure(figsize=(8, 5))
plt.barh(top.feature, top.strength, color="#2f6fdb")
plt.title("Top 10 features by univariate strength |AUC - 0.5|"); plt.tight_layout(); plt.show()

# COMMAND ----------

fig, axes = plt.subplots(2, 3, figsize=(17, 8))
for ax, col in zip(axes.flat, ["usage_change_pct", "support_interactions_l3m", "tenure_months_at_obs",
                               "days_to_contract_end", "avg_resolution_days_l90", "avg_csat_l90"]):
    d = pdf[[col, "is_churned"]].dropna()
    lo, hi = d[col].quantile([0.01, 0.99])
    d = d[d[col].between(lo, hi)]
    bins = np.histogram_bin_edges(d[col], bins=30)
    ax.hist(d.loc[d.is_churned == 0, col], bins=bins, density=True, alpha=0.55, color="#2f6fdb", label="active")
    ax.hist(d.loc[d.is_churned == 1, col], bins=bins, density=True, alpha=0.55, color="#e34a33", label="churned")
    ax.set_title(col); ax.legend()
plt.tight_layout(); plt.show()

# COMMAND ----------

corr = pdf[num_cols].corr()
plt.figure(figsize=(13, 11))
plt.imshow(corr, cmap="coolwarm", vmin=-1, vmax=1)
plt.colorbar(shrink=0.8)
plt.xticks(range(len(corr)), corr.columns, rotation=90, fontsize=8)
plt.yticks(range(len(corr)), corr.columns, fontsize=8)
plt.grid(False); plt.title("Correlation matrix"); plt.tight_layout(); plt.show()

# COMMAND ----------

pairs = corr.where(np.triu(np.ones(corr.shape, dtype=bool), 1)).stack()
display(pairs[pairs.abs() > 0.8].sort_values(key=abs, ascending=False).rename("corr").reset_index())

# COMMAND ----------

pdf["declining_usage"] = (pdf.usage_change_pct < -0.15).astype(int)
pdf["high_support_load"] = (pdf.support_interactions_l3m >= 4).astype(int)
seg = pdf.groupby(["declining_usage", "high_support_load"]).is_churned.agg(["mean", "size"]).round(3)
display(seg.reset_index())

# COMMAND ----------

