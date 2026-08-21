global topdir "/Users/wanghaiyu/Desktop/Econ681/"
local datadir "$topdir/cleaned"
local dodir "$topdir/do"

import delimited using "`datadir'/nlsy79_cleaned_2.csv", clear

encode race, gen(race_cat)
encode occ, gen(occ_cat)
replace experience = experience / 52
gen experience_2 = experience^2

** Summary Statistics
local id caseid
preserve
keep if !missing(log_wage, hrly_wage, experience, occ, hgcrev, asvab, sex, race)
keep if hrly_wage < 300 // manually checked hrly_wage between 100 - 1000, found that hrly wage bellow 300 is a reasonable one
keep if hrly_wage >= 1 
summarize log_wage hrly_wage experience occ_cat asvab
bysort `id': keep if _n == 1
summarize sex race_cat hgcrev age 
summarize hrly_wage, detail
restore

** Regression
// Model 1
reg log_wage hgcrev asvab c.hgcrev#c.experience c.asvab#c.experience experience experience_2 age i.sex i.race_cat i.year [pweight = sampweight], vce(cluster caseid)

// Model 2
reg log_wage hgcrev ib1.occ_cat##(c.asvab c.experience) experience_2 ///
	age i.sex i.race_cat i.year ///
	[pweight = sampweight], vce(cluster caseid)

// Model 3
reg log_wage hgcrev asvab experience experience_2 ///
    c.hgcrev#c.experience c.asvab#c.experience ib1.occ_cat ///
    ib1.occ_cat#c.asvab ib1.occ_cat#c.experience ///
    ib1.occ_cat#c.asvab#c.experience c.age i.sex i.race_cat i.year ///
    [pweight=sampweight], vce(cluster caseid)
	
** Testing employer learning heterogeneity
testparm i.occ_cat#c.asvab#c.experience

// employer learning effect in occupation
lincom c.asvab#c.experience // reference group clerical
lincom c.asvab#c.experience + 2.occ_cat#c.asvab#c.experience // occupation 2
