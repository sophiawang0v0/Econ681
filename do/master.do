global topdir "/Users/wanghaiyu/Desktop/Econ681/"
local datadir "$topdir/cleaned"
local dodir "$topdir/do"

import delimited using "`datadir'/nlsy_merged.csv", clear

encode race, gen(race_cat)
encode occ, gen(occ_cat)
encode sex, gen(sex_cat)

** winsorize 
winsor2 wage, cuts(1 99) replace

gen lnwage = ln(wage)
gen lnwage100 = 100 * lnwage
gen exp_2 = exp^2
gen exp_3 = exp^3
gen tenure_2 = tenure^2
gen tenure_3 = tenure^3

keep if (cohort == 0 & year <= 2004) | cohort == 1
keep if job_num <=3

** Summary Table

summarize exp hour tenure wage cohort age
tab occ_cat cohort, col nofreq

preserve
egen personid = group(cohort id)
collapse (mean) wage hour exp tenure educ ///
         (firstnm) asvab cohort sex_cat race_cat, ///
         by(personid)
summarize asvab educ sex_cat race_cat
restore

** Table 2: Baseline and occupation models

* Common explanatory variables
local rhs c.educ c.asvab ///
    c.exp c.exp_2 c.exp_3 ///
    c.tenure c.tenure_2 c.tenure_3 ///
    c.educ#c.exp c.asvab#c.exp ///
    c.educ#c.tenure c.asvab#c.tenure

* Common controls
local controls ib1.job_num i.year i.sex_cat i.race_cat

foreach c in 0 1 {

    ** Baseline regression without occupations
    regress lnwage100 `rhs' `controls' ///
        if cohort == `c' & inrange(job_num, 1, 3) ///
        [pweight = sampleweight], vce(cluster id)

    estimates store BASE_`c'

    * Tests of cubic terms
    test exp_3
    test tenure_3
    test exp_3 tenure_3

    ** Second regression with occupation interactions
    regress lnwage100 ///
        ib1.occ_cat##(`rhs') `controls' ///
        if cohort == `c' & inrange(job_num, 1, 3) ///
        [pweight = sampleweight], vce(cluster id)

    estimates store OLS_`c'

    * Tests of cubic terms across all occupations
    testparm c.exp_3 i.occ_cat#c.exp_3

    testparm c.tenure_3 i.occ_cat#c.tenure_3

    testparm c.exp_3 i.occ_cat#c.exp_3 ///
        c.tenure_3 i.occ_cat#c.tenure_3
}

** Display four columns in the requested order
* Column 1: NLSY79 baseline
* Column 2: NLSY97 baseline
* Column 3: NLSY79 occupation model, clerical coefficients
* Column 4: NLSY97 occupation model, clerical coefficients

estimates table BASE_0 BASE_1 OLS_0 OLS_1, ///
    keep(educ asvab exp tenure ///
         c.educ#c.exp c.asvab#c.exp ///
         c.educ#c.tenure c.asvab#c.tenure) ///
    b(%9.3f) se(%9.3f) p(%9.4f) ///
    stats(N N_clust r2) ///
    varwidth(24) modelwidth(12)

** Linear combination tests for Panel B of Table 2
foreach model in BASE_0 BASE_1 OLS_0 OLS_1 {

    estimates restore `model'

    display "Model: `model'"

    * Education: experience interaction plus tenure interaction
    lincom c.educ#c.exp + c.educ#c.tenure

    * ASVAB: experience interaction plus tenure interaction
    lincom c.asvab#c.exp + c.asvab#c.tenure
}

* Output to tex file
local terms c.educ c.educ#c.exp c.educ#c.tenure ///
    c.asvab c.asvab#c.exp c.asvab#c.tenure

* Open the LaTeX output file
capture mkdir "$topdir/tables"
file open out using "$topdir/tables/table2_occupation.tex", ///
    write replace

* Table heading
file write out "\begin{table}[p]\centering" _n
file write out "\caption{Education, Ability, and Wage Dynamics by Occupation}" _n
file write out "\label{tab:ols_learning}" _n
file write out "\begin{threeparttable}\footnotesize" _n
file write out "\setlength{\tabcolsep}{3pt}" _n
file write out "\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lrrrrrr@{}}" _n
file write out "\toprule" _n
file write out "& \multicolumn{3}{c}{Education} & \multicolumn{3}{c}{ASVAB} \\" _n
file write out "\cmidrule(lr){2-4}\cmidrule(lr){5-7}" _n
file write out "Occupation & Level & \(\times\) Experience & \(\times\) Tenure & Level & \(\times\) Experience & \(\times\) Tenure \\" _n
file write out "& (1) & (2) & (3) & (4) & (5) & (6) \\ \midrule" _n

foreach c in 0 1 {

    * Restore the full cohort regression
    estimates restore OLS_`c'

    * Express all entries on the scale of 100 times log wages
    assert inlist("`e(depvar)'", "lnwage", "lnwage100")
    local scale = cond("`e(depvar)'" == "lnwage100", 1, 100)

    local panel "A. NLSY79"
    if `c' == 1 local panel "B. NLSY97"

    file write out "\addlinespace \multicolumn{7}{l}{`panel'} \\" _n

    * Calculate the six coefficients for each occupation
    forvalues o = 1/7 {

        local occupation : label (occ_cat) `o'
		local brow "`occupation'"
		local serow ""

		if `o' == 4 {
			local brow "Operatives and"
			local serow "laborers"
		}

        foreach term of local terms {
            * Clerical uses the main coefficient
            local expression "`term'"
            * Other occupations
            if `o' != 1 ///
                local expression "`term' + `o'.occ_cat#`term'"
            quietly lincom `scale' * (`expression')
            * Extract the estimate, standard error, and significance
            local b : display %6.3f r(estimate)
            local se : display %6.3f r(se)
            local stars = cond(r(p)<0.01,"***", ///
                cond(r(p)<0.05,"**", ///
                cond(r(p)<0.10,"*","")))
            local brow "`brow' & \(`b'^{`stars'}\)"
            local serow "`serow' & (`se')"
        }
        file write out "`brow' \\" _n
        file write out "`serow' \\" _n
    }
    * Joint equality tests across occupations
    local prow "Equality test, \(p\)"
    foreach term of local terms {
        quietly testparm i.occ_cat#`term'
        local p : display %6.4f r(p)
        if r(p) < 0.001 local p "\(<0.001\)"
        local prow "`prow' & `p'"
    }
    file write out "\addlinespace `prow' \\" _n
    * Model statistics
    local N : display %12.0fc e(N)
    local G : display %12.0fc e(N_clust)
    local R2 : display %6.4f e(r2)
    file write out "\multicolumn{7}{l}{Observations: `N'; Respondents: `G'; \(R^2=`R2'\).} \\" _n
}
* Table notes
file write out "\bottomrule\end{tabular*}" _n
file write out "\begin{tablenotes}[flushleft]\scriptsize" _n

file write out "\item Note. Each panel reports one unweighted OLS regression. Estimates and standard errors are expressed on the scale of 100 times log real hourly wages. Entries are total occupation coefficients. Standard errors clustered by respondent are in parentheses. " _n

file write out "Wages are winsorized at the 1st and 99th percentiles of the pooled merged dataset before restricting job numbers to 1 through 3. Education, experience, and tenure are in years. ASVAB is in principal component units. Level coefficients apply at zero experience and tenure. " _n

file write out "Both regressions include sex and race controls. Equality tests compare the corresponding coefficient across all seven occupations." _n

file write out "\item \(^{*}p<0.10\); \(^{**}p<0.05\); \(^{***}p<0.01\)." _n
file write out "\end{tablenotes}\end{threeparttable}\end{table}" _n

file close out


** IV Regression
*** NLSY79
ivregress 2sls lnwage100 ///
    educ asvab tenure tenure_2 tenure_3 ///
    c.educ#c.tenure c.asvab#c.tenure ///
    i.job_num i.year i.sex_cat i.race_cat ///
    (exp exp_2 exp_3 c.educ#c.exp c.asvab#c.exp = ///
     potexp potexp_2 potexp_3 educ_potexp asvab_potexp) ///
    if cohort == 0 [pweight = sampleweight], ///
    vce(cluster id) first

estat firststage, all

*** NLSY97
ivregress 2sls lnwage100 ///
    educ asvab tenure tenure_2 tenure_3 ///
    c.educ#c.tenure c.asvab#c.tenure ///
    i.job_num i.year i.sex_cat i.race_cat ///
    (exp exp_2 exp_3 c.educ#c.exp c.asvab#c.exp = ///
     potexp potexp_2 potexp_3 educ_potexp asvab_potexp) ///
    if cohort == 1 [pweight = sampleweight], ///
    vce(cluster id) first

estat firststage, all

foreach c in 0 1 {
quietly ivreg2 lnwage100 ///
        educ asvab tenure tenure_2 tenure_3 ///
        c.educ#c.tenure c.asvab#c.tenure ///
        i.job_num i.year i.sex_cat i.race_cat ///
        (exp exp_2 exp_3 c.educ#c.exp c.asvab#c.exp = ///
         potexp potexp_2 potexp_3 educ_potexp asvab_potexp) ///
        if cohort == `c' [pweight = sampleweight], ///
        cluster(id) first savesfirst
		
		* Preserve the IV results
tempname iv_original
estimates store `iv_original'

* Access the saved first stage system
estimates restore _ivreg2_sfirst_lnwage100

matrix FS = J(5,5,.)
local j = 0

foreach y in exp exp_2 exp_3 c.educ#c.exp c.asvab#c.exp {
    local ++j
    local i = 0

    foreach z in potexp potexp_2 potexp_3 educ_potexp asvab_potexp {
        local ++i
        matrix FS[`i',`j'] = _b[`y':`z']
    }
}

matrix rownames FS = P P2 P3 SP ZP
matrix colnames FS = E E2 E3 SE ZE

matlist FS, format(%10.4f) rowtitle(Instrument)

estimates restore `iv_original'
}

foreach c in 0 1 {

    ivreg2 lnwage100 ///
        educ asvab tenure tenure_2 tenure_3 ///
        c.educ#c.tenure c.asvab#c.tenure ///
        i.job_num i.year i.sex_cat i.race_cat ///
        (exp exp_2 exp_3 c.educ#c.exp c.asvab#c.exp ///
         ib4.occ_code = ///
         potexp potexp_2 potexp_3 educ_potexp asvab_potexp ///
         i.occ_l1##i.occ_l2) ///
        if cohort == `c' & occ_iv_ready == 1 ///
        [pweight = sampleweight], cluster(id) first

    estimates store OCC_IV_`c'
}


** Testing employer learning heterogeneity
testparm i.occ_cat#c.asvab#c.experience

// employer learning effect in occupation
lincom c.asvab#c.experience // reference group clerical
lincom c.asvab#c.experience + 2.occ_cat#c.asvab#c.experience // occupation 2
