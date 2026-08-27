global topdir "/Users/wanghaiyu/Desktop/Econ681/"
local datadir "$topdir/cleaned"
local dodir "$topdir/do"

import delimited using "`datadir'/nlsy79_cleaned.csv", clear

encode race, gen(race_cat)
encode occ, gen(occ_cat)
encode sex, gen(sex_cat)
gen lnwage = ln(wage)
gen experience_2 = experience^2

** winsorize 
winsor2 wage, cuts(1 99) replace

** Summary Statistics
egen group = cut(experience), group(100)

** Regression
// Model 1
reg lnwage educ asvab c.educ#c.experience c.asvab#c.experience experience experience_2 age i.sex_cat i.race_cat i.year [pweight = sampleweight], vce(cluster caseid)

// Model 2
reg lnwage educ ib1.occ_cat##(c.asvab c.experience) experience_2 ///
	age i.sex_cat i.race_cat i.year ///
	[pweight = sampleweight], vce(cluster caseid)

// Model 3
reg lnwage educ asvab experience experience_2 ///
    c.educ#c.experience c.asvab#c.experience ib1.occ_cat ///
    ib1.occ_cat#c.asvab ib1.occ_cat#c.experience ///
    ib1.occ_cat#c.asvab#c.experience c.age i.sex_cat i.race_cat i.year ///
    [pweight=sampleweight], vce(cluster caseid)
	
** Testing employer learning heterogeneity
testparm i.occ_cat#c.asvab#c.experience

// employer learning effect in occupation
lincom c.asvab#c.experience // reference group clerical
lincom c.asvab#c.experience + 2.occ_cat#c.asvab#c.experience // occupation 2
