global topdir "/Users/wanghaiyu/Desktop/Econ681/"
local datadir "$topdir/cleaned"
local dodir "$topdir/do"

import delimited using "`datadir'/nlsy79_cleaned_2.csv", clear

encode race, gen(race_cat)
encode occ, gen(occ_cat)
replace tenure = tenure / 52
gen tenure_2 = tenure^2

** Summary Statistics

*** Job 1
local id caseid
preserve
keep if !missing(log_wage01, hrly_wage01, tenure01, occ01_cat, hgcrev, asvab, sex, race)
keep if hrly_wage01 <1000
summarize hrly_wage01 hgcrev tenure01 occ01_cat asvab
bysort `id': keep if _n == 1
summarize sex race_cat
restore
*** Job 2
local id caseid
preserve
keep if !missing(log_wage02, hrly_wage02, tenure02, rti02, hgcrev, asvab, sex, race)
keep if hrly_wage02 <1000
summarize hrly_wage02 hgcrev tenure02 rti02 asvab
bysort `id': keep if _n == 1
summarize sex race_cat
restore

** Regression
// Model 1
reg log_wage hgcrev asvab c.hgcrev#c.tenure c.asvab#c.tenure tenure tenure_2 age i.sex i.race_cat i.year [pweight = sampweight], vce(cluster caseid)

// Model 2
reg log_wage hgcrev ib1.occ_cat##(c.asvab c.tenure) tenure_2 ///
	age i.sex i.race_cat i.year ///
	[pweight = sampweight], vce(cluster caseid)

// Model 3
reg log_wage hgcrev asvab tenure tenure_2 ///
    c.hgcrev#c.tenure c.asvab#c.tenure ib1.occ_cat ///
    ib1.occ_cat#c.asvab ib1.occ_cat#c.tenure ///
    ib1.occ_cat#c.asvab#c.tenure c.age i.sex i.race_cat i.year ///
    [pweight=sampweight], vce(cluster caseid)
