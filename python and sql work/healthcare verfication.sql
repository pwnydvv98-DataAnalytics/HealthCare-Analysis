set global local_infile = 1;
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean table1/clean_dim_admissions.csv"
into table clean_dim_admissions
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean table1/clean_dim_patients.csv"
into table clean_dim_patients
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;
load data infile "C:/ProgramData/MySQL/MySQL Server 8.0/Uploads/clean table1/clean_fact_patient_billing.csv"
into table clean_fact_patient_billing
fields terminated by ','
enclosed by '"'
lines terminated by '\n'
ignore 1 rows;

select "clean_dim_patients" as table_name,count(*) as row_count,
sum(case when gender not in ("Male","Female","Other") then 1 else 0 end ) as issue_count
from clean_dim_patients
union all
select "clean_dim_admissions" as table_name ,count(*) as row_count,
sum(case when discharge_date < admission_date or length_of_stay_days < 1 then 1 else 0 end ) as issue_count
from clean_dim_admissions
union all 
select "clean_fact_patient_billing" ,count(*) as row_count,
sum(case when charge_amount <= 0 or patient_liability_amount < 0 then 1 else 0 end) as issue_count
from clean_fact_patient_billing;