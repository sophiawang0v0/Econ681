"""Format the Stata baseline IV estimates as two concise LaTeX tables."""
import csv
import sys
from pathlib import Path

folder = Path(sys.argv[1])

def read(name):
    with (folder / name).open(newline='') as stream:
        return {(int(r['cohort']), r['term']): r for r in csv.DictReader(stream)}

first = read('firststage.csv')
second = read('secondstage.csv')
endogenous = ['exp', 'exp_2', 'exp_3', 'educ_exp', 'asvab_exp']
terms = ['educ', 'educ_exp', 'educ_tenure', 'asvab', 'asvab_exp',
         'asvab_tenure', 'exp', 'exp_2', 'exp_3', 'tenure', 'tenure_2', 'tenure_3']
assert len(first) == 10 and len(second) == 24
for c in (0, 1):
    for term in endogenous:
        assert float(first[c, term]['N']) == float(second[c, term]['N'])
        assert float(first[c, term]['clusters']) == float(second[c, term]['clusters'])

labels = {
    'educ': 'Schooling', 'educ_exp': r'Schooling $\times$ experience',
    'educ_tenure': r'Schooling $\times$ tenure', 'asvab': 'ASVAB',
    'asvab_exp': r'ASVAB $\times$ experience',
    'asvab_tenure': r'ASVAB $\times$ tenure',
    'exp': 'Experience', 'exp_2': r'Experience$^2$', 'exp_3': r'Experience$^3$',
    'tenure': 'Tenure', 'tenure_2': r'Tenure$^2$', 'tenure_3': r'Tenure$^3$',
}
short = {'exp': '$E$', 'exp_2': '$E^2$', 'exp_3': '$E^3$',
         'educ_exp': '$S E$', 'asvab_exp': '$Z E$'}

def number(x, digits=3):
    return f'{float(x):.{digits}f}'

def count(c, key):
    return f"{int(float(first[c, 'exp'][key])):,}"

first_lines = [r'\begin{table}[p]\centering',
    r'\caption{Baseline IV: First stage relevance}\label{tab:baseline_iv_firststage}',
    r'\begin{threeparttable}\small',
    r'\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lrrrrrr@{}}',
    r'\toprule',
    r'& \multicolumn{3}{c}{NLSY79} & \multicolumn{3}{c}{NLSY97} \\',
    r'\cmidrule(lr){2-4}\cmidrule(lr){5-7}',
    r'Endogenous regressor & $F$ & Partial $R^2$ & Shea $R^2$ & $F$ & Partial $R^2$ & Shea $R^2$ \\',
    r'\midrule']
for term in endogenous:
    values = [short[term]]
    for c in (0, 1):
        r = first[c, term]
        values += [number(r['F'], 2), number(r['partial_r2']), number(r['shea_r2'])]
    first_lines.append(' & '.join(values) + r' \\')
first_lines += [r'\midrule']
for key, label in [('N', 'Observations'), ('clusters', 'Respondents')]:
    first_lines.append(label + r' & \multicolumn{3}{c}{' + count(0, key) +
                       r'} & \multicolumn{3}{c}{' + count(1, key) + r'} \\')
first_lines += [r'\bottomrule\end{tabular*}',
    r'\begin{tablenotes}[flushleft]\footnotesize',
    r'\item Notes. $E$ denotes actual experience, $S$ schooling, and $Z$ ASVAB. '
    r'Each row summarizes one first stage, including all five excluded instruments '
    r'$(P,P^2,P^3,SP,ZP)$ and all exogenous controls. $P$ is years since first observed employment.',
    r'\item The $F$ statistics test joint significance of the five excluded instruments, '
    r'with standard errors clustered by respondent. These are equation tests, not conditional '
    r'$F$ tests. Shea\textquotesingle s partial $R^2$ accounts for relationships among the '
    r'endogenous regressors. Sampling weights are applied.',
    r'\end{tablenotes}\end{threeparttable}\end{table}']

second_lines = [r'\begin{table}[p]\centering',
    r'\caption{Baseline IV: Second stage wage equation}\label{tab:baseline_iv_secondstage}',
    r'\begin{threeparttable}\small',
    r'\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}lrr@{}}',
    r'\toprule', r'& NLSY79 & NLSY97 \\', r'\midrule']
for i, term in enumerate(terms):
    if i in (3, 6, 9):
        second_lines.append(r'\addlinespace[3pt]')
    second_lines.append(labels[term] + ' & ' +
                        ' & '.join('$' + number(second[c, term]['b'], 4) + '$' for c in (0, 1)) + r' \\')
    second_lines.append(' & ' + ' & '.join('(' + number(second[c, term]['se'], 4) + ')' for c in (0, 1)) + r' \\')
second_lines += [r'\midrule']
for key, label in [('N', 'Observations'), ('clusters', 'Respondents')]:
    second_lines.append(label + ' & ' + count(0, key) + ' & ' + count(1, key) + r' \\')
second_lines += [r'\bottomrule\end{tabular*}',
    r'\begin{tablenotes}[flushleft]\footnotesize',
    r'\item Notes. The dependent variable is 100 times log real hourly wage. '
    r'Entries are 2SLS coefficients, with standard errors clustered by respondent in parentheses. '
    r'Sampling weights are applied. Both models include job spell, year, sex, and race controls; '
    r'occupation terms are excluded.',
    r'\item The endogenous terms are $(E,E^2,E^3,SE,ZE)$, instrumented by '
    r'$(P,P^2,P^3,SP,ZP)$. Other regressors are treated as exogenous. '
    r'Schooling and ASVAB level coefficients apply at zero experience and tenure.',
    r'\item The sample retains job numbers 1 through 3 and NLSY79 observations through 2004. '
    r'Wages are winsorized at the pooled 1st and 99th percentiles before sample restrictions.',
    r'\end{tablenotes}\end{threeparttable}\end{table}']

first_tex = '\n'.join(first_lines) + '\n'
second_tex = '\n'.join(second_lines) + '\n'
(folder / 'table_baseline_firststage.tex').write_text(first_tex)
(folder / 'table_baseline_secondstage.tex').write_text(second_tex)
preamble = r'''\documentclass[11pt]{article}
\usepackage[letterpaper,margin=0.9in]{geometry}
\usepackage[T1]{fontenc}
\usepackage{tgpagella}
\usepackage{booktabs,threeparttable,textcomp}
\usepackage{caption}
\captionsetup[table]{font=small,labelfont=normalfont,labelsep=newline,justification=centering}
\setlength{\tabcolsep}{5pt}
\setlength{\parindent}{0pt}
\begin{document}
'''
(folder / 'baseline_iv_tables.tex').write_text(preamble + first_tex + '\n\\clearpage\n' + second_tex + '\n\\end{document}\n')
print('Formatted two baseline IV tables from verified Stata estimates.')
