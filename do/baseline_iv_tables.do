version 18.0
set more off
args output
if "`output'" == "" local output "/Users/wanghaiyu/Desktop/Econ681/tables/baseline_iv"
capture mkdir "`output'"
capture log close baseline_iv
log using "`output'/baseline_iv.log", text replace name(baseline_iv)

* Match the sample preparation in master.do.
import delimited "/Users/wanghaiyu/Desktop/Econ681/cleaned/nlsy_merged.csv", clear
encode race, gen(race_cat)
encode sex, gen(sex_cat)
winsor2 wage, cuts(1 99) replace
gen lnwage = ln(wage)
gen lnwage100 = 100 * lnwage
gen exp_2 = exp^2
gen exp_3 = exp^3
gen tenure_2 = tenure^2
gen tenure_3 = tenure^3
gen double educ_exp = educ * exp
gen double asvab_exp = asvab * exp
gen double educ_tenure = educ * tenure
gen double asvab_tenure = asvab * tenure
keep if (cohort == 0 & year <= 2004) | cohort == 1
keep if inrange(job_num, 1, 3)

local controls educ asvab tenure tenure_2 tenure_3 educ_tenure asvab_tenure ///
    ib1.job_num i.year i.sex_cat i.race_cat
local endogenous exp exp_2 exp_3 educ_exp asvab_exp
local instruments potexp potexp_2 potexp_3 educ_potexp asvab_potexp
local reported educ educ_exp educ_tenure asvab asvab_exp asvab_tenure ///
    exp exp_2 exp_3 tenure tenure_2 tenure_3

tempname diagnostics coefficients
postfile `diagnostics' byte cohort str16 term double F partial_r2 shea_r2 N clusters ///
    using "`output'/firststage.dta", replace
postfile `coefficients' byte cohort str16 term double b se p N clusters r2 ///
    using "`output'/secondstage.dta", replace

foreach c in 0 1 {
    * This single command estimates both stages of the full baseline.
    ivregress 2sls lnwage100 `controls' (`endogenous' = `instruments') ///
        if cohort == `c' [pweight = sampleweight], vce(cluster id) first
    estimates store IV_baseline_`c'
    estimates save "`output'/IV_baseline_`c'.ster", replace
    local N_`c' : display %12.0fc e(N)
    local G_`c' : display %12.0fc e(N_clust)
    estat firststage, all
    matrix D = r(singleresults)
    matrix S = r(multiresults)
    matrix FS_`c' = D[1..5,4], D[1..5,3], S[1..5,1]
    matrix rownames FS_`c' = exp exp_2 exp_3 educ_exp asvab_exp
    matrix colnames FS_`c' = F Partial_R2 Shea_R2
    local i = 0
    foreach term of local endogenous {
        local ++i
        post `diagnostics' (`c') ("`term'") (D[`i',4]) (D[`i',3]) ///
            (S[`i',1]) (e(N)) (e(N_clust))
    }
    foreach term of local reported {
        quietly lincom `term'
        post `coefficients' (`c') ("`term'") (r(estimate)) (r(se)) (r(p)) ///
            (e(N)) (e(N_clust)) (e(r2))
    }
}
postclose `diagnostics'
postclose `coefficients'

esttab matrix(FS_0, fmt(2 3 3)) using "`output'/firststage.rtf", replace ///
    nomtitles nonumbers varwidth(28) modelwidth(12) ///
    title("Baseline IV: First stage relevance, NLSY79") ///
    coeflabels(exp "Experience" exp_2 "Experience squared" ///
        exp_3 "Experience cubed" educ_exp "Schooling x experience" ///
        asvab_exp "ASVAB x experience")
esttab matrix(FS_1, fmt(2 3 3)) using "`output'/firststage.rtf", append ///
    nomtitles nonumbers varwidth(28) modelwidth(12) ///
    title("Baseline IV: First stage relevance, NLSY97") ///
    coeflabels(exp "Experience" exp_2 "Experience squared" ///
        exp_3 "Experience cubed" educ_exp "Schooling x experience" ///
        asvab_exp "ASVAB x experience") ///
    addnotes("Each row summarizes one first stage with all five excluded instruments and all exogenous controls." ///
        "F tests the joint significance of the five instruments, with clustering by respondent." ///
        "NLSY79: `N_0' observations and `G_0' respondents. NLSY97: `N_1' observations and `G_1' respondents." ///
        "Sampling weights are applied. These are equation F statistics, not conditional F statistics.")

* A compact second stage table that opens in Word.
esttab IV_baseline_0 IV_baseline_1 using "`output'/secondstage.rtf", replace ///
    b(4) se(4) nostar nonumbers nogaps varwidth(30) modelwidth(13) ///
    mtitles("NLSY79" "NLSY97") keep(`reported') order(`reported') ///
    coeflabels(educ "Schooling" educ_exp "Schooling x experience" ///
        educ_tenure "Schooling x tenure" asvab "ASVAB" ///
        asvab_exp "ASVAB x experience" asvab_tenure "ASVAB x tenure" ///
        exp "Experience" exp_2 "Experience squared" exp_3 "Experience cubed" ///
        tenure "Tenure" tenure_2 "Tenure squared" tenure_3 "Tenure cubed") ///
    stats(N N_clust, fmt(%12.0fc %12.0fc) labels("Observations" "Respondents")) ///
    title("Baseline IV: Second stage") nonotes ///
    addnotes("Dependent variable: 100 times log real hourly wage." ///
        "Standard errors clustered by respondent are in parentheses. Sampling weights are applied." ///
        "Both models include job spell, year, sex, and race controls, with no occupation terms." ///
        "Five experience terms are instrumented by the corresponding potential experience terms.")

preserve
use "`output'/firststage.dta", clear
export delimited using "`output'/firststage.csv", replace
list, noobs abbreviate(16)
use "`output'/secondstage.dta", clear
export delimited using "`output'/secondstage.csv", replace
list, noobs abbreviate(16)
restore
display "BASELINE_IV_TABLES_COMPLETE"
log close baseline_iv
