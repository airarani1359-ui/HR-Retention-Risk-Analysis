-- =====================================================================
-- Retention & Risk Analysis | MySQL 8
-- Author: Aiswarya Rani
-- Database: hr_retention (departments, employees, performance, exits)
-- Flow: tables -> attrition drivers -> exit analysis (window functions)
--       -> flight-risk score -> validation -> action list
-- =====================================================================

CREATE DATABASE IF NOT EXISTS hr_retention;
USE hr_retention;
CREATE TABLE departments (
  dept_id   INT PRIMARY KEY,
  dept_name VARCHAR(40),
  division  VARCHAR(30)
);
CREATE TABLE employees (
  emp_id             INT PRIMARY KEY,
  gender             VARCHAR(10),
  age                INT,
  nationality_group  VARCHAR(20),
  education          VARCHAR(20),
  dept_id            INT,
  job_title          VARCHAR(40),
  job_level          INT,
  hire_date          DATE,
  monthly_salary_aed INT,
  overtime           VARCHAR(3)
);
CREATE TABLE performance (
  emp_id             INT,
  review_year        INT,
  performance_rating INT,
  job_satisfaction   INT,
  work_life_balance  INT,
  training_hours     INT
);
CREATE TABLE exits (
  emp_id      INT PRIMARY KEY,
  exit_date   DATE,
  exit_type   VARCHAR(15),
  exit_reason VARCHAR(40)
);

-- Data loaded with MySQL Workbench > Table Data Import Wizard
-- Row counts: departments 7 | employees 1140 | performance 1140 | exits 239

-- Q1 Overall headcount, leavers, attrition rate
SELECT COUNT(*) AS employees,
       COUNT(x.emp_id) AS leavers,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
LEFT JOIN exits x ON e.emp_id = x.emp_id;

-- Q2 Attrition by department
SELECT d.dept_name,
       COUNT(*) AS employees,
       COUNT(x.emp_id) AS leavers,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
GROUP BY d.dept_name
ORDER BY attrition_rate_pct DESC;

-- Q3 Attrition by overtime
SELECT e.overtime,
       COUNT(*) AS employees,
       COUNT(x.emp_id) AS leavers,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
LEFT JOIN exits x ON e.emp_id = x.emp_id
GROUP BY e.overtime;

-- Q4 Attrition by job level
SELECT e.job_level,
       COUNT(*) AS employees,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
LEFT JOIN exits x ON e.emp_id = x.emp_id
GROUP BY e.job_level
ORDER BY e.job_level;

-- Q5 Attrition by tenure band
SELECT CASE
         WHEN TIMESTAMPDIFF(MONTH, e.hire_date, COALESCE(x.exit_date, '2025-12-31')) < 12 THEN '1. Under 1 year'
         WHEN TIMESTAMPDIFF(MONTH, e.hire_date, COALESCE(x.exit_date, '2025-12-31')) < 24 THEN '2. 1-2 years'
         WHEN TIMESTAMPDIFF(MONTH, e.hire_date, COALESCE(x.exit_date, '2025-12-31')) < 60 THEN '3. 2-5 years'
         ELSE '4. 5+ years'
       END AS tenure_band,
       COUNT(*) AS employees,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
LEFT JOIN exits x ON e.emp_id = x.emp_id
GROUP BY tenure_band
ORDER BY tenure_band;

-- Q6 Attrition by job satisfaction
SELECT p.job_satisfaction,
       COUNT(*) AS employees,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM employees e
JOIN performance p ON e.emp_id = p.emp_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
GROUP BY p.job_satisfaction
ORDER BY p.job_satisfaction;

-- Q7 Overtime x department (where is overtime hurting most?)
SELECT d.dept_name,
       ROUND(100 * SUM(CASE WHEN e.overtime = 'Yes' AND x.emp_id IS NOT NULL THEN 1 ELSE 0 END)
                 / NULLIF(SUM(e.overtime = 'Yes'), 0), 1) AS attrition_with_ot_pct,
       ROUND(100 * SUM(CASE WHEN e.overtime = 'No'  AND x.emp_id IS NOT NULL THEN 1 ELSE 0 END)
                 / NULLIF(SUM(e.overtime = 'No'), 0), 1)  AS attrition_without_ot_pct
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
GROUP BY d.dept_name
ORDER BY attrition_with_ot_pct DESC;

-- Q8 Salary position within job level (NTILE window function)
WITH ranked AS (
  SELECT e.emp_id,
         NTILE(4) OVER (PARTITION BY e.job_level ORDER BY e.monthly_salary_aed, e.emp_id) AS pay_quartile
  FROM employees e
)
SELECT CONCAT('Q', r.pay_quartile, CASE r.pay_quartile WHEN 1 THEN ' (lowest pay)' WHEN 4 THEN ' (highest pay)' ELSE '' END) AS pay_quartile_in_level,
       COUNT(*) AS employees,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct
FROM ranked r
LEFT JOIN exits x ON r.emp_id = x.emp_id
GROUP BY r.pay_quartile
ORDER BY r.pay_quartile;

-- Q9 Leavers vs stayers: average profile
SELECT CASE WHEN x.emp_id IS NULL THEN 'Stayed' ELSE 'Left' END AS status,
       COUNT(*) AS employees,
       ROUND(AVG(e.monthly_salary_aed)) AS avg_salary_aed,
       ROUND(AVG(p.job_satisfaction), 2) AS avg_satisfaction,
       ROUND(AVG(p.work_life_balance), 2) AS avg_work_life_balance,
       ROUND(AVG(p.training_hours), 1) AS avg_training_hours,
       ROUND(100 * AVG(e.overtime = 'Yes'), 1) AS pct_on_overtime
FROM employees e
JOIN performance p ON e.emp_id = p.emp_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
GROUP BY status;

-- Q10 Exit reasons with share of voluntary exits (window function)
SELECT exit_reason,
       COUNT(*) AS leavers,
       ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS share_pct
FROM exits
WHERE exit_type = 'Voluntary'
GROUP BY exit_reason
ORDER BY leavers DESC;

-- Q11 Regretted attrition: high performers who left voluntarily
SELECT d.dept_name,
       COUNT(*) AS high_performers_lost
FROM exits x
JOIN employees e   ON x.emp_id = e.emp_id
JOIN performance p ON x.emp_id = p.emp_id
JOIN departments d ON e.dept_id = d.dept_id
WHERE x.exit_type = 'Voluntary' AND p.performance_rating >= 4
GROUP BY d.dept_name
ORDER BY high_performers_lost DESC;

-- Q12 Monthly exits in 2025 with running total
SELECT DATE_FORMAT(exit_date, '%Y-%m') AS month,
       COUNT(*) AS exits,
       SUM(COUNT(*)) OVER (ORDER BY DATE_FORMAT(exit_date, '%Y-%m')) AS running_total
FROM exits
GROUP BY DATE_FORMAT(exit_date, '%Y-%m')
ORDER BY month;

-- Q13 Department ranking by attrition (RANK)
SELECT d.dept_name,
       ROUND(100 * COUNT(x.emp_id) / COUNT(*), 1) AS attrition_rate_pct,
       RANK() OVER (ORDER BY COUNT(x.emp_id) / COUNT(*) DESC) AS attrition_rank
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
GROUP BY d.dept_name
ORDER BY attrition_rank;

-- Q14 Emiratisation snapshot: UAE Nationals share of current headcount by department
SELECT d.dept_name,
       COUNT(*) AS active_headcount,
       SUM(e.nationality_group = 'UAE National') AS uae_nationals,
       ROUND(100 * SUM(e.nationality_group = 'UAE National') / COUNT(*), 1) AS uae_national_pct
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
WHERE x.emp_id IS NULL
GROUP BY d.dept_name
ORDER BY uae_national_pct;

-- Q15 Flight-risk score for current employees (CASE points)
CREATE OR REPLACE VIEW vw_flight_risk AS
SELECT e.emp_id, d.dept_name, e.job_title, e.job_level, e.monthly_salary_aed, e.overtime,
       p.job_satisfaction, p.work_life_balance,
       TIMESTAMPDIFF(MONTH, e.hire_date, '2025-12-31') AS tenure_months,
         (CASE WHEN e.overtime = 'Yes' THEN 3 ELSE 0 END)
       + (CASE WHEN p.job_satisfaction <= 2 THEN 2 ELSE 0 END)
       + (CASE WHEN p.work_life_balance = 1 THEN 1 ELSE 0 END)
       + (CASE WHEN TIMESTAMPDIFF(MONTH, e.hire_date, '2025-12-31') < 24 THEN 2 ELSE 0 END)
       + (CASE WHEN e.job_level = 1 THEN 1 ELSE 0 END) AS risk_score
FROM employees e
JOIN departments d ON e.dept_id = d.dept_id
JOIN performance p ON e.emp_id = p.emp_id
LEFT JOIN exits x  ON e.emp_id = x.emp_id
WHERE x.emp_id IS NULL;

SELECT CASE WHEN risk_score >= 6 THEN '1. High' WHEN risk_score >= 3 THEN '2. Medium' ELSE '3. Low' END AS risk_level,
       COUNT(*) AS current_employees
FROM vw_flight_risk
GROUP BY risk_level
ORDER BY risk_level;

-- Q15b Does the risk score work? Apply the same points to everyone and compare with who actually left
WITH scored AS (
  SELECT e.emp_id, x.emp_id AS left_id,
           (CASE WHEN e.overtime = 'Yes' THEN 3 ELSE 0 END)
         + (CASE WHEN p.job_satisfaction <= 2 THEN 2 ELSE 0 END)
         + (CASE WHEN p.work_life_balance = 1 THEN 1 ELSE 0 END)
         + (CASE WHEN TIMESTAMPDIFF(MONTH, e.hire_date, COALESCE(x.exit_date, '2025-12-31')) < 24 THEN 2 ELSE 0 END)
         + (CASE WHEN e.job_level = 1 THEN 1 ELSE 0 END) AS risk_score
  FROM employees e
  JOIN performance p ON e.emp_id = p.emp_id
  LEFT JOIN exits x  ON e.emp_id = x.emp_id
)
SELECT CASE WHEN risk_score >= 6 THEN '1. High' WHEN risk_score >= 3 THEN '2. Medium' ELSE '3. Low' END AS risk_level,
       COUNT(*) AS employees,
       COUNT(left_id) AS actually_left,
       ROUND(100 * COUNT(left_id) / COUNT(*), 1) AS attrition_rate_pct
FROM scored
GROUP BY risk_level
ORDER BY risk_level;

-- Q16 Top 3 highest-risk employees in each department (ROW_NUMBER)
WITH ranked AS (
  SELECT emp_id, dept_name, job_title, risk_score, tenure_months,
         ROW_NUMBER() OVER (PARTITION BY dept_name ORDER BY risk_score DESC, tenure_months) AS rn
  FROM vw_flight_risk
)
SELECT dept_name, emp_id, job_title, risk_score, tenure_months
FROM ranked
WHERE rn <= 3
ORDER BY dept_name, rn;

-- Export for HR: high-risk current employees (saved as high_risk_employees.csv)
SELECT * FROM vw_flight_risk WHERE risk_score >= 6 ORDER BY risk_score DESC, tenure_months;
