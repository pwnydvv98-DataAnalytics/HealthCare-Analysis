create table clean_dim_patients as
select 
	patient_id,
    case 
		when trim(gender) in ("female","f") then "Female"
        when trim(gender) in ("male","m") then "Male"
        when trim(gender) = "other" then "Other"
        else "Other"
	end as gender,
    trim(age) as age,
    case
		when insurance_provider in ("None","UNKNOWN","null","nan"," ") then "Unassigned"
		else trim(insurance_provider)
	end as insurance_provider,
    chronic_condition_flag
from dim_patients;

   --- fact_admissions
   
create table clean_fact_admission as
select 
	admission_id,
    patient_id,
    dept_id,
    physician_id,
    case
		when discharge_date<admission_date then admission_date
        else admission_date
	end as admission_date,
    case
		when discharge_date < admission_date then admission_date
        else discharge_date
	end as discharge_date,
    trim(admission_type) as admission_type,
    greatest(
		1,
        ceil(
			timestampdiff(second,
				case when discharge_date<admission_date then discharge_date else admission_date end,
                case when discharge_date < admission_date then admission_date else discharge_date end)/86400.0))
	as length_of_stay_days,
    trim(discharge_status) as discharge_status
from fact_admissions;

--- fact_patient_billing 
select 
	count(*) as total_rows,
    count(distinct billing_id) as unique_billing_id,
    count(*) - count(distinct billing_id) as duplicate_rows_count,
    sum(case when charge_amount <= 0 then 1 else 0 end) as invalid_negative_charges,
    sum(case when patient_liability_amount < 0 then 1 else 0 end) as invalid_negative_liabilities
from fact_patient_billing;

--- clean the table fact_patient_billing
create table clean_fact_patient_billing as 
with ranked_billing as(
select 
	billing_id,
    admission_id,
    charge_category,
    charge_amount,
    insurance_coverage_pct,
    claim_settlement_status,
    row_number()over(partition by billing_id order by billing_id) as row_num
from fact_patient_billing
)
select
	billing_id,
    admission_id,
    charge_category,
    charge_amount,
    insurance_coverage_pct,
    round(charge_amount * (1.0 - insurance_coverage_pct),2) as patient_liability_amount,
    claim_settlement_status
from ranked_billing
where row_num = 1 and charge_amount >0;

--- recheking & verification 
select "clean_dim_patients" as table_name,count(*) as row_count,
sum(case when gender not in ("Male","Female","Other") then 1 else 0 end ) as issue_count
from clean_dim_patients
union all
select "clean_fact_admissions" as table_name ,count(*) as row_count,
sum(case when discharge_date < admission_date or length_of_stay_days < 1 then 1 else 0 end ) as issue_count
from clean_fact_admission
union all 
select "clean_fact_patient_billing" ,count(*) as row_count,
sum(case when charge_amount <= 0 or patient_liability_amount < 0 then 1 else 0 end) as issue_count
from clean_fact_patient_billing;

--- SQL ANALYTICS & BUSINESS PROBLEM SOLVING
--- Bed Occupancy & Department Bottleneck Analysis

select 
	d.dept_id,
    d.dept_name,
    d.ward_type,
    d.bed_capacity,
    count(a.admission_id) as total_admission,
    round(avg(a.length_of_stay_days),2) as avg_length_of_stay_days,
    sum(a.length_of_stay_days) as total_inpatient_days_occupied,
    round((sum(a.length_of_stay_days)*100.0)/(d.bed_capacity * 608.0),2) as bed_occupancy_rate_pct
from dim_departments d 
left join clean_fact_admission a 
	on d.dept_id = a.dept_id
group by d.dept_id,d.dept_name,d.ward_type,d.bed_capacity
order by bed_occupancy_rate_pct desc;

--- 30 days readmission Risk & Demographic Drivers
select 
	case 
		when p.age < 30 then '<30'
        when p.age between 30 and 60 then '30-60'
        else '>60'
	end as age_group,
    a.admission_type,
    p.chronic_condition_flag,
    count(a.admission_id) as total_admission,
    sum(case when a.discharge_status = 'Readmitted within 30d' then 1 else 0 end) as readmitted_30d_count,
    round(sum(case when a.discharge_status = 'Readmitted within 30d' then 1.0 else 0.0 end) * 100.0 / count(a.admission_id),2) as readmission_rate_pct
from clean_fact_admission a 
join clean_dim_patients p 
	on a.patient_id = p.patient_id
group by 
case 
		when p.age < 30 then '<30'
        when p.age between 30 and 60 then '30-60'
        else '>60'
	end,
    a.admission_type,
    p.chronic_condition_flag
order by readmission_rate_pct desc;

--- revenue leakage via denied claims by insurance provider
select 
	coalesce(p.insurance_provider,'Unassigned') as insurance_provider,
    count(pb.billing_id) as total_billing,
    round(sum(pb.charge_amount),2) as total_billing_revenue,
    sum(case when pb.claim_settlement_status = 'Claim Denied' then 1 else 0 end) as denied_claim_count,
    round(sum(case when pb.claim_settlement_status = 'Claim Denied' then pb.charge_amount else 0.0 end),2) as total_denied_revenue_lose,
    round(sum(case when pb.claim_settlement_status = 'Claim Denied' then pb.charge_amount else 0.0 end )*100 / sum(pb.charge_amount),2) as denied_loss_pct,
    round(sum(case when pb.claim_settlement_status = 'Claim Denied' then 1.0 else 0.0 end)*100.0/count(pb.billing_id),2) as denial_claim_count_pct
from clean_fact_patient_billing pb
join clean_fact_admission a 
	on pb.admission_id = a.admission_id
left join clean_dim_patients p 
	on p.patient_id = a.patient_id
group by 
coalesce(p.insurance_provider,'Unassigned')
order by 
total_denied_revenue_lose desc;

--- departmental revenue & physician performance
select 
	d.dept_name,
    count(distinct a.admission_id) as  total_stays,
    round(avg(a.length_of_stay_days),1) as avg_los,
    round(sum(pb.charge_amount),2) as total_department_revenue,
    round(sum(pb.charge_amount)/count(distinct a.admission_id),2) as revenue_per_stay,
    round(sum(pb.patient_liability_amount),2) as out_of_pocket_patient_share
from clean_fact_patient_billing pb
join clean_fact_admission a 
	on pb.admission_id = a.admission_id
join dim_departments d 
	on a.dept_id = d.dept_id
group by d.dept_name order by total_department_revenue desc;