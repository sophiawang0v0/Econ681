version 18.0
set more off

* Run this file separately. It reproduces the linear IV specification.
* Optional argument changes the output folder.
args output
if "`output'" == "" local output "/Users/wanghaiyu/Desktop/Econ681/tables"
capture mkdir "`output'"
capture log close fs_simple
log using "`output'/firststage_simple.log", text replace name(fs_simple)

import delimited "/Users/wanghaiyu/Desktop/Econ681/cleaned/nlsy_merged.csv", clear
encode race, gen(race_cat)
encode sex, gen(sex_cat)
winsor2 wage, cuts(1 99) replace
gen lnwage100 = 100 * ln(wage)
keep if (cohort == 0 & year <= 2004) | cohort == 1
keep if job_num <= 3

local controls educ asvab tenure i.job_num i.year i.sex_cat i.race_cat
foreach c in 0 1 {
    * One command estimates the IV model for each cohort.
    ivregress 2sls lnwage100 `controls' (exp = potexp) ///
        if cohort == `c' [pweight = sampleweight], vce(cluster id)
    estimates store IV_linear_`c'
    estat firststage
    matrix diagnostics = r(singleresults)
    local partial_r2 = diagnostics[1,3]

    * Display and store the first stage on exactly the same IV sample.
    regress exp potexp `controls' if e(sample) ///
        [pweight = sampleweight], vce(cluster id)
    test potexp
    estadd scalar excluded_F = r(F)
    estadd scalar partial_r2 = `partial_r2'
    estimates store FS_linear_`c'
}

* Open the resulting RTF table in Word.
esttab FS_linear_0 FS_linear_1 using "`output'/firststage_simple.rtf", ///
    replace b(3) se(3) nostar nonumbers varwidth(34) modelwidth(12) ///
    mtitles("NLSY79" "NLSY97") ///
    keep(potexp) coeflabels(potexp "Potential experience (years)") ///
    stats(excluded_F partial_r2 r2 N N_clust, fmt(2 3 3 %12.0fc %12.0fc) ///
        labels("Excluded instrument F statistic" "Partial R squared" ///
        "R squared" "Observations" "Respondents")) ///
    title("First stage: Actual experience (years)") ///
    nonotes addnotes("Standard errors clustered by respondent are in parentheses." ///
        "Both columns control for schooling, ASVAB, tenure, job number, year, sex, and race." ///
        "Sampling weights are applied. Each column uses its corresponding IV estimation sample." ///
        "Potential experience is the survey year minus the earliest observed employment entry year." ///
        "The F statistic tests whether the coefficient on potential experience is zero.")

estimates table FS_linear_0 FS_linear_1, keep(potexp) b(%9.6f) se(%9.6f) ///
    stats(excluded_F partial_r2 r2 N N_clust)
display "Saved: `output'/firststage_simple.rtf"
log close fs_simple
