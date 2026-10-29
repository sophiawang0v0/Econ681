version 18.0
set more off

* Run separately from master.do. No second stage is estimated.
* Optional first argument: wave (default) or annual for occupation histories.
args history_timing
if "`history_timing'" == "" local history_timing "wave"
if !inlist("`history_timing'", "wave", "annual") {
    display as error "Use wave or annual as the optional argument."
    exit 198
}

capture program drop econ681_firststage_current
program define econ681_firststage_current
    version 18.0
    args history_timing
    local datafile "/Users/wanghaiyu/Desktop/Econ681/cleaned/nlsy_merged.csv"
    local output "/Users/wanghaiyu/Desktop/Econ681/do/firststage_current_results"
    capture mkdir "`output'"
    local output "`output'/`history_timing'"
    capture mkdir "`output'"
    capture log close fs_current
    log using "`output'/firststage.log", text replace name(fs_current)
    import delimited using "`datafile'", clear varnames(1) case(lower) asdouble
    isid cohort id year job_num
    foreach v in potexp potexp_2 potexp_3 educ_potexp asvab_potexp ///
                 occ_code occ_l1 occ_l2 occ_iv_ready occ_iv_annual {
        confirm numeric variable `v'
    }
    encode race, gen(race_cat)
    encode sex, gen(sex_cat)
    * Use the notebook's explicit occupation codes, not alphabetical encode codes.
    label define current_occ 1 "Professional" 2 "Managers" 3 "Sales" ///
        4 "Clerical" 5 "Craftsmen" 6 "Operatives and Laborers" 7 "Service", replace
    label values occ_code current_occ

    * Reproduce the pooled wage winsorization in master.do for sample eligibility.
    * These native commands implement winsor2 wage, cuts(1 99) replace.
    quietly _pctile wage, p(1 99)
    local lower = r(r1)
    local upper = r(r2)
    quietly replace wage = max(min(wage, `upper'), `lower') if !missing(wage)
    gen double lnwage100 = 100 * ln(wage)
    gen double exp_2 = exp^2
    gen double exp_3 = exp^3
    gen double tenure_2 = tenure^2
    gen double tenure_3 = tenure^3
    gen double educ_exp = educ * exp
    gen double asvab_exp = asvab * exp
    gen double educ_tenure = educ * tenure
    gen double asvab_tenure = asvab * tenure
    local endogenous exp exp_2 exp_3 educ_exp asvab_exp
    local potential potexp potexp_2 potexp_3 educ_potexp asvab_potexp
    local controls c.educ c.asvab c.tenure c.tenure_2 c.tenure_3 ///
        c.educ_tenure c.asvab_tenure ib1.job_num i.year i.sex_cat i.race_cat

    * Baseline assumption: schooling, ASVAB, tenure and its interactions are exogenous.
    * No occupation variables enter this baseline specification.
    egen byte missing_base = rowmiss(lnwage100 cohort id year job_num ///
        exp exp_2 exp_3 educ_exp asvab_exp tenure tenure_2 tenure_3 ///
        educ asvab educ_tenure asvab_tenure sex_cat race_cat sampleweight)
    gen byte eligible = missing_base == 0 & sampleweight > 0 ///
        & inrange(job_num, 1, 3) ///
        & ((cohort == 0 & year <= 2004) | cohort == 1)
    egen byte missing_iv = rowmiss(`potential')
    gen byte sample_experience = eligible & missing_iv == 0
    gen byte sample_occupation = sample_experience & occ_iv_ready == 1
    if "`history_timing'" == "annual" ///
        replace sample_occupation = sample_occupation & occ_iv_annual == 1
    forvalues j = 1/6 {
        gen byte occupation`j' = occ_code == `j' if !missing(occ_code)
    }

    tempname coefficients diagnostics samples
    postfile `coefficients' byte cohort str24 model str32 dependent str32 instrument ///
        double b se p byte omitted using "`output'/coefficients.dta", replace
    postfile `diagnostics' byte cohort str24 model str32 dependent str12 tested ///
        double N clusters r2 partial_r2 F df_num df_den p ///
        int excluded_count test_rc str16 omitted_pair ///
        using "`output'/diagnostics.dta", replace
    postfile `samples' byte cohort double eligible experience occupation people_exp people_occ ///
        using "`output'/samples.dta", replace

    foreach c in 0 1 {
        quietly count if eligible & cohort == `c'
        local neligible = r(N)
        quietly count if sample_experience & cohort == `c'
        local nexp = r(N)
        quietly count if sample_occupation & cohort == `c'
        local nocc = r(N)
        tempvar exp_tag occ_tag
        quietly egen byte `exp_tag' = tag(id) if sample_experience & cohort == `c'
        quietly count if `exp_tag' == 1
        local gexp = r(N)
        quietly egen byte `occ_tag' = tag(id) if sample_occupation & cohort == `c'
        quietly count if `occ_tag' == 1
        local gocc = r(N)
        drop `exp_tag' `occ_tag'
        post `samples' (`c') (`neligible') (`nexp') (`nocc') (`gexp') (`gocc')

        foreach model in experience occupation_screen {
            local sample sample_experience
            local dependent_list `endogenous'
            local excluded `potential'
            local reference ""
            local history
            if "`model'" == "occupation_screen" {
                local sample sample_occupation
                local dependent_list occupation1 occupation2 occupation3 ///
                    occupation4 occupation5 occupation6
                * Omit one observed pair with the intercept; skip all empty pairs.
                forvalues j = 1/7 {
                    forvalues k = 1/7 {
                        quietly count if `sample' & cohort == `c' & zocc_`j'`k' == 1
                        if r(N) > 0 {
                            if "`reference'" == "" local reference "zocc_`j'`k'"
                            else local history `history' zocc_`j'`k'
                        }
                    }
                }
                local excluded `potential' `history'
            }
            local nz : word count `excluded'
            foreach dependent of local dependent_list {
                quietly regress `dependent' `controls' if `sample' & cohort == `c' ///
                    [pweight=sampleweight], vce(cluster id)
                local restricted_rss = e(rss)
                local restricted_N = e(N)

                * EACH first stage includes ALL excluded instruments and controls.
                quietly regress `dependent' `controls' `excluded' ///
                    if `sample' & cohort == `c' ///
                    [pweight=sampleweight], vce(cluster id)
                assert e(N) == `restricted_N'
                local n = e(N)
                local clusters = e(N_clust)
                local r2 = e(r2)
                local partial = .
                if `restricted_rss' > 0 local partial = max(0, 1 - e(rss)/`restricted_rss')
                estimates save "`output'/FS_`c'_`dependent'.ster", replace
                foreach instrument of local excluded {
                    quietly lincom `instrument'
                    post `coefficients' (`c') ("`model'") ("`dependent'") ///
                        ("`instrument'") (r(estimate)) (r(se)) (r(p)) (r(se) == 0)
                }
                local blocks all
                if "`model'" == "occupation_screen" & "`history'" != "" local blocks all history
                foreach block of local blocks {
                    local tested `excluded'
                    if "`block'" == "history" local tested `history'
                    capture quietly test `tested'
                    local rc = _rc
                    local f = .
                    local df1 = .
                    local df2 = .
                    local p = .
                    if `rc' == 0 {
                        local f = r(F)
                        local df1 = r(df)
                        local df2 = r(df_r)
                        local p = r(p)
                    }
                    post `diagnostics' (`c') ("`model'") ("`dependent'") ("`block'") ///
                        (`n') (`clusters') (`r2') (`partial') (`f') (`df1') (`df2') (`p') ///
                        (`nz') (`rc') ("`reference'")
                }
            }
        }
    }
    postclose `coefficients'
    postclose `diagnostics'
    postclose `samples'
    foreach name in coefficients diagnostics samples {
        use "`output'/`name'.dta", clear
        export delimited using "`output'/`name'.csv", replace
    }
    use "`output'/diagnostics.dta", clear
    format partial_r2 p %9.4f
    format F %9.2f
    list cohort model dependent N clusters partial_r2 F df_num p if tested == "all", ///
        noobs sepby(cohort model) abbreviate(24)
    * Refresh the tables from the saved estimates after every successful run.
    local table_python "/Users/wanghaiyu/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
    local table_exporter "/Users/wanghaiyu/Desktop/Econ681/do/export_firststage_tables.py"
    confirm file "`table_python'"
    confirm file "`table_exporter'"
    capture erase "`output'/table_export_success.txt"
    shell "`table_python'" "`table_exporter'" "`output'" "`history_timing'"
    confirm file "`output'/table_export_success.txt"
    display "Presentation tables: `output'/firststage_tables.pdf"
    display "Completed. Results: `output'"
    display "occupation_screen is a prediction check, not the full Gibbons first stage system."
    display "Its regressions omit the many endogenous interactions needed by the full occupation wage model."
    display "partial_r2 describes ALL excluded instruments, including in the history test rows."
    display "These ordinary joint F tests do not establish conditional strength or instrument validity."
end

* Restore the user's open dataset, including if execution encounters an error.
preserve
capture noisily econ681_firststage_current "`history_timing'"
local rc = _rc
capture log close fs_current
restore
capture program drop econ681_firststage_current
if `rc' exit `rc'
