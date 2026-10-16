import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns

# patients table clean
df_patients = pd.read_csv("C:/Users/pwnyd/Desktop/100k above datasets/healthcare/dim_patients.csv")
gender_mapping = {
    "male" : "Male",
    "m" : "Male",
    "female" : "Female",
    "f" : "Female",
    "other" : "Other"
}
df_patients["gender"] = (
    df_patients["gender"].astype(str).str.strip().str.lower().map(gender_mapping).fillna("Other")
)
#insurance_provider
df_patients["insurance_provider"] = df_patients["insurance_provider"].replace(["UNKNOWN","null","None",np.nan],"Unassigned")
df_patients["gender"] = df_patients["gender"].astype("category")
df_patients["insurance_provider"]= df_patients["insurance_provider"].astype("category")
df_patients["chronic_condition_flag"] = df_patients["chronic_condition_flag"].astype("int8")
df_patients["age"] = df_patients["age"].astype("int8")

# fact_admission table
df_admissions = pd.read_csv("C:/Users/pwnyd/Desktop/100k above datasets/healthcare/fact_admissions.csv")
df_admissions["admission_date"] = pd.to_datetime(df_admissions["admission_date"])
df_admissions["discharge_date"] = pd.to_datetime(df_admissions["discharge_date"])
inverted_mask = (df_admissions["discharge_date"] < df_admissions["admission_date"])
inverted_count = inverted_mask.sum()
temp_admissions = df_admissions.loc[inverted_mask,"admission_date"].copy()
df_admissions.loc[inverted_mask,"admission_date"] = df_admissions.loc[inverted_mask,"discharge_date"]
df_admissions.loc[inverted_mask,"discharge_date"]=temp_admissions
los_seconds = (
df_admissions["discharge_date"]-df_admissions["admission_date"]).dt.total_seconds()
df_admissions["length_of_stay_days"] = (
    np.ceil(los_seconds / 86400.0).astype(int).clip(lower = 1)
)
valid_patient_ids = set(df_admissions["patient_id"])
df_admissions["is_orphan_patient"] = ~df_admissions["patient_id"].isin(valid_patient_ids)
orphan_count = df_admissions["is_orphan_patient"].sum()
df_admissions["admission_type"] = df_admissions["admission_type"].astype("category")
df_admissions["discharge_status"] = df_admissions["discharge_status"].astype("category")

# clean fact_patient_billing
df_billing = pd.read_csv("C:/Users/pwnyd/Desktop/100k above datasets/healthcare/fact_patient_billing.csv")
# print(df_billing)
initial_billing_rows = len(df_billing)
#deduplicate logging entries
df_billing = df_billing.drop_duplicates(subset=["billing_id"]).copy()
dupes_removed = initial_billing_rows - len(df_billing)
#remove corrupted negative charge records
invalid_charge = (df_billing["charge_amount"]<=0).sum()
df_billing = df_billing[df_billing["charge_amount"]>0].copy()
#mathematically recompute corrupted patient liability amounts
df_billing["patient_liability_amount"] = np.round(df_billing["charge_amount"]*(1.0 - df_billing["insurance_coverage_pct"]),2,)
#downcast datatypes
df_billing["charge_category"] = df_billing["charge_category"].astype("category")
df_billing["claim_settlement_status"] = df_billing["claim_settlement_status"].astype("category")
df_billing["charge_amount"] = df_billing["charge_amount"].astype("float32")
df_billing["patient_liability_amount"] = df_billing["patient_liability_amount"].astype("float32")


# EXPORT files
df_patients.to_csv("clean_dim_patients.csv",index=False)
df_admissions.to_csv("clean_dim_admissions.csv",index=False)
df_billing.to_csv("clean_fact_patient_billing.csv",index=False)
