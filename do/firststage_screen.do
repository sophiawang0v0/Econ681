version 18.0
set more off

* First stage screening only. No wage regression or instrument selection.
* Run this file as a separate do file. master.do is not changed.
* Optional arguments: data CSV, prepared instrument CSV, output directory.
args datafile ivfile outdir
if `"`datafile'"' == "" local datafile "/Users/wanghaiyu/Desktop/Econ681/cleaned/nlsy_merged.csv"
if `"`ivfile'"' == "" local ivfile "/Users/wanghaiyu/Desktop/Econ681/do/firststage_instruments.csv"
if `"`outdir'"' == "" local outdir "/Users/wanghaiyu/Desktop/Econ681/do"

* The instrument CSV must have one row per cohort id year job_num.
* Required columns: cohort id year job_num potexp lag1_occ lag2_occ z_t z_t2.
* potexp: validated elapsed time since initial labor market entry.
* lag1_occ and lag2_occ: actual main occupation in the preceding survey waves.
* Occupation codes: 1 Clerical; 2 Craftsmen; 3 Managers;
* 4 Operatives and Laborers; 5 Professional; 6 Sales; 7 Service.
* z_t and z_t2: separately prepared candidate instruments for T and T squared.
* If using job mean deviations, z_t2 is the deviation of T squared from its
* job mean, not the square of z_t. Job means require validated employer spells
* and appropriate handling of sampling weights and the final analysis sample.
* Missing history is missing, not occupation zero or a fabricated prior job.
* Do not use arbitrary row lags or the first retained year as market entry.
* The current CSV has multiple jobs in some person years and lacks these IVs.
* See firststage_instruments_TEMPLATE.csv for the required column headings.
* Candidate instruments and their products require substantive validity checks.

capture program drop econ681_fs_screen
program define econ681_fs_screen
    version 18.0
    args datafile ivfile outdir

    confirm file "`datafile'"
    capture confirm file "`ivfile'"
    if _rc {
        display as error "Prepared instrument file not found: `ivfile'"
        display as error "Supply potexp, lag1_occ, lag2_occ, z_t, z_t2, and the four row keys."
        display as error "No first stages have been estimated."
        exit 601
    }

    import delimited using "`ivfile'", clear varnames(1) case(lower)
    foreach v in cohort id year job_num potexp lag1_occ lag2_occ z_t z_t2 {
        confirm numeric variable `v'
    }
    assert _N > 0
    isid cohort id year job_num
    assert inlist(cohort, 0, 1)
    foreach v in lag1_occ lag2_occ {
        assert inrange(`v', 1, 7) & `v' == floor(`v') if !missing(`v')
    }
    assert potexp >= 0 if !missing(potexp)
    keep cohort id year job_num potexp lag1_occ lag2_occ z_t z_t2
    tempfile instruments
    save `instruments'

    import delimited using "`datafile'", clear varnames(1) case(lower)
    isid cohort id year job_num
    encode race, gen(race_cat)
    encode sex, gen(sex_cat)
    label define occupation_codes 1 "Clerical" 2 "Craftsmen" 3 "Managers" ///
        4 "Operatives and Laborers" 5 "Professional" 6 "Sales" 7 "Service", replace
    encode occ, gen(occ_cat) label(occupation_codes) noextend
    merge 1:1 cohort id year job_num using `instruments', ///
        keep(master match) gen(iv_match)

    capture mkdir "`outdir'"
    capture log close econ681_fs_log
    log using "`outdir'/firststage.log", text replace name(econ681_fs_log)

    * Use one common sample for every first stage in each cohort.
    egen byte baseline_missing = rowmiss(cohort id year job_num exp tenure ///
        educ asvab occ_cat sex_cat race_cat sampleweight wage)
    gen byte eligible = baseline_missing == 0 & sampleweight > 0 & wage > 0 ///
        & exp >= 0 & tenure >= 0 & inrange(job_num, 1, 3) ///
        & ((cohort == 0 & year <= 2004) | cohort == 1)
    egen byte iv_missing = rowmiss(potexp lag1_occ lag2_occ z_t z_t2)
    gen byte fs_sample = eligible & iv_missing == 0 & iv_match == 3
    display "Eligible observations and observations with all instrument inputs:"
    tabulate cohort fs_sample if eligible, missing

    * Quadratic model: both experience and tenure are endogenous.
    gen double exp_2 = exp^2
    gen double tenure_2 = tenure^2
    gen double s_exp = educ * exp
    gen double a_exp = asvab * exp
    gen double s_ten = educ * tenure
    gen double a_ten = asvab * tenure
    local endog exp exp_2 tenure tenure_2 s_exp a_exp s_ten a_ten
    forvalues j = 2/7 {
        gen byte o`j' = occ_cat == `j' if !missing(occ_cat)
        local endog `endog' o`j'
        foreach v in educ asvab s_exp a_exp s_ten a_ten {
            gen double o`j'_`v' = o`j' * `v'
            local endog `endog' o`j'_`v'
        }
    }

    * Candidate instrument blocks. No actual tenure appears on the RHS.
    gen double z_p = potexp
    gen double z_p2 = potexp^2
    gen double z_sp = educ * potexp
    gen double z_ap = asvab * potexp
    gen double z_st = educ * z_t
    gen double z_at = asvab * z_t
    local z_exp z_p z_p2 z_sp z_ap
    local z_ten z_t z_t2 z_st z_at
    local z_hist
    forvalues j = 1/7 {
        forvalues k = 1/7 {
            if !(`j' == 1 & `k' == 1) {
                gen byte z_h`j'`k' = lag1_occ == `j' & lag2_occ == `k' ///
                    if !missing(lag1_occ, lag2_occ)
                local z_hist `z_hist' z_h`j'`k'
            }
        }
    }
    local z_inter
    forvalues j = 2/7 {
        foreach v in educ asvab z_sp z_ap z_st z_at {
            gen double z_l`j'_`v' = (lag2_occ == `j') * `v' if !missing(lag2_occ)
            local z_inter `z_inter' z_l`j'_`v'
        }
    }
    local excluded `z_exp' `z_ten' `z_hist' `z_inter'
    local controls c.educ c.asvab ib1.job_num i.year i.sex_cat i.race_cat

    tempname cf dg au
    postfile `cf' byte cohort str32 dependent str32 instrument ///
        double b se p byte omitted using "`outdir'/firststage_coefficients.dta", replace
    postfile `dg' byte cohort str32 dependent str16 block ///
        double N clusters r2 partial_r2 F df_num df_den p int test_rc ///
        using "`outdir'/firststage_tests.dta", replace
    postfile `au' byte cohort double eligible complete people ///
        using "`outdir'/firststage_sample.dta", replace

    foreach c in 0 1 {
        quietly count if eligible & cohort == `c'
        local neligible = r(N)
        quietly count if fs_sample & cohort == `c'
        local ncomplete = r(N)
        tempvar person_tag
        quietly egen byte `person_tag' = tag(id) if fs_sample & cohort == `c'
        quietly count if `person_tag' == 1
        local people = r(N)
        drop `person_tag'
        post `au' (`c') (`neligible') (`ncomplete') (`people')

        foreach dependent of local endog {
            capture confirm variable fit_`dependent'
            if _rc gen double fit_`dependent' = .
            quietly summarize `dependent' if fs_sample & cohort == `c'
            if r(N) < 2 | r(min) == r(max) {
                display as error "Cohort `c', `dependent': no sample or no outcome variation."
                post `dg' (`c') ("`dependent'") ("not_estimable") ///
                    (`ncomplete') (`people') (.) (.) (.) (.) (.) (.) (2000)
                continue
            }

            * Restricted regression supplies the denominator of partial R squared.
            quietly regress `dependent' `controls' if fs_sample & cohort == `c' ///
                [pweight = sampleweight], vce(cluster id)
            local rss_restricted = e(rss)

            * Every dependent variable uses all the same candidate instruments.
            quietly regress `dependent' `controls' `excluded' ///
                if fs_sample & cohort == `c' ///
                [pweight = sampleweight], vce(cluster id)
            assert e(N) == `ncomplete'
            local n = e(N)
            local g = e(N_clust)
            local r2 = e(r2)
            local partial = .
            if `rss_restricted' > 0 local partial = max(0, 1 - e(rss)/`rss_restricted')
            estimates save "`outdir'/FS_`c'_`dependent'.ster", replace
            if inlist("`dependent'", "exp", "tenure") estimates replay
            tempvar fitted
            quietly predict double `fitted' if e(sample), xb
            quietly replace fit_`dependent' = `fitted' if e(sample)
            drop `fitted'

            foreach instrument of local excluded {
                quietly lincom `instrument'
                post `cf' (`c') ("`dependent'") ("`instrument'") ///
                    (r(estimate)) (r(se)) (r(p)) (r(se) == 0)
            }

            * Joint tests condition on all the other instruments and controls.
            * partial_r2 always describes the full excluded instrument set.
            * These block tests are not conditional weak identification tests.
            foreach block in all experience tenure history interactions {
                local tested `excluded'
                if "`block'" == "experience" local tested `z_exp'
                if "`block'" == "tenure" local tested `z_ten'
                if "`block'" == "history" local tested `z_hist'
                if "`block'" == "interactions" local tested `z_inter'
                capture quietly test `tested'
                local test_rc = _rc
                local f = .
                local numerator = .
                local denominator = .
                local p = .
                if `test_rc' == 0 {
                    local f = r(F)
                    local numerator = r(df)
                    local denominator = r(df_r)
                    local p = r(p)
                }
                post `dg' (`c') ("`dependent'") ("`block'") ///
                    (`n') (`g') (`r2') (`partial') ///
                    (`f') (`numerator') (`denominator') (`p') (`test_rc')
            }
        }
    }
    postclose `cf'
    postclose `dg'
    postclose `au'

    keep if fs_sample
    keep cohort id year job_num sampleweight occ_cat fit_*
    save "`outdir'/firststage_fitted_values.dta", replace
    foreach file in firststage_coefficients firststage_tests firststage_sample {
        use "`outdir'/`file'.dta", clear
        export delimited using "`outdir'/`file'.csv", replace
    }
    use "`outdir'/firststage_tests.dta", clear
    format F %9.2f
    format p partial_r2 %9.4f
    list cohort dependent N clusters partial_r2 F p test_rc ///
        if block == "all" | block == "not_estimable", noobs sepby(cohort)
    display "Completed first stage screening. Output directory: `outdir'"
    display "Joint F tests here are not conditional weak IV diagnostics for the full system."
    display "Do not apply automatic coefficient or p value cutoffs to select instruments."
end

* Preserve the data currently open in Stata, including when an input check fails.
preserve
capture noisily econ681_fs_screen "`datafile'" "`ivfile'" "`outdir'"
local screening_rc = _rc
capture log close econ681_fs_log
restore
capture program drop econ681_fs_screen
if `screening_rc' exit `screening_rc'
