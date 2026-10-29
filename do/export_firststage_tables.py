"""Format saved Stata estimates as journal tables. Never reestimate or alter data.

Usage: python export_firststage_tables.py RESULTS_DIR [wave|annual] [OUTPUT_DIR]
Requires reportlab, available in the configured Codex Python runtime.
"""
import csv
import hashlib
import html
import json
import math
from pathlib import Path
import sys

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT, TA_RIGHT
from reportlab.lib.pagesizes import letter
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, PageBreak

DEPENDENTS = ['exp', 'exp_2', 'exp_3', 'educ_exp', 'asvab_exp']
INSTRUMENTS = ['potexp', 'potexp_2', 'potexp_3', 'educ_potexp', 'asvab_potexp']
DEPENDENT_LABELS = ['E', 'E2', 'E3', 'S x E', 'A x E']
INSTRUMENT_LABELS = ['P', 'P2', 'P3', 'S x P', 'A x P']
OCCUPATIONS = ['Professional', 'Managers', 'Sales', 'Clerical', 'Craftsmen', 'Operatives and laborers']
PAPER = 'https://lkatz.scholars.harvard.edu/sites/g/files/omnuum5961/files/lkatz/files/gklp_jole_2005.pdf'


def read_rows(path):
    with path.open(newline='') as stream:
        return list(csv.DictReader(stream))


def fnum(value, digits=2):
    return f'{float(value):,.{digits}f}'


def pvalue(value):
    return '<0.001' if float(value) < 0.001 else f'{float(value):.3f}'


def stars(value):
    p = float(value)
    return '***' if p < 0.01 else '**' if p < 0.05 else '*' if p < 0.10 else ''


def math_label(value, tex=False):
    labels = {
        'E': ('<i>E</i>', r'$E$'), 'E2': ('<i>E</i><super>2</super>', r'$E^2$'),
        'E3': ('<i>E</i><super>3</super>', r'$E^3$'),
        'S x E': ('<i>S</i> × <i>E</i>', r'$S\times E$'),
        'A x E': ('<i>A</i> × <i>E</i>', r'$A\times E$'),
        'P': ('<i>P</i>', r'$P$'), 'P2': ('<i>P</i><super>2</super>', r'$P^2$'),
        'P3': ('<i>P</i><super>3</super>', r'$P^3$'),
        'S x P': ('<i>S</i> × <i>P</i>', r'$S\times P$'),
        'A x P': ('<i>A</i> × <i>P</i>', r'$A\times P$'),
        'Partial R squared': ('Partial <i>R</i><super>2</super>', r'Partial $R^2$'),
        'R squared': ('<i>R</i><super>2</super>', r'$R^2$'),
        'Full set partial R2': ('Full set partial <i>R</i><super>2</super>', r'Full set partial $R^2$'),
    }
    return labels.get(value, (html.escape(value), value))[int(tex)]


def load_and_check(results):
    coefficients = read_rows(results / 'coefficients.csv')
    diagnostics = read_rows(results / 'diagnostics.csv')
    samples = read_rows(results / 'samples.csv')
    cindex = {(int(r['cohort']), r['dependent'], r['instrument']): r
              for r in coefficients if r['model'] == 'experience'}
    dindex = {(int(r['cohort']), r['model'], r['dependent'], r['tested']): r for r in diagnostics}
    assert len(dindex) == len(diagnostics), 'Duplicate diagnostic rows'
    assert len(cindex) == 50, 'Expected 50 experience coefficients'
    sindex = {int(r['cohort']): r for r in samples}
    for cohort in (0, 1):
        for dependent in DEPENDENTS:
            d = dindex[cohort, 'experience', dependent, 'all']
            assert int(d['test_rc']) == 0 and int(d['df_num']) == 5
            assert float(d['N']) == float(sindex[cohort]['experience'])
            assert float(d['clusters']) == float(sindex[cohort]['people_exp'])
            assert 0 <= float(d['partial_r2']) <= 1
            assert all(math.isfinite(float(d[k])) for k in ['F', 'p', 'r2', 'partial_r2'])
            for instrument in INSTRUMENTS:
                row = cindex[cohort, dependent, instrument]
                assert int(row['omitted']) == 0
                assert math.isfinite(float(row['b'])) and float(row['se']) > 0
        for j in range(1, 7):
            for block in ('all', 'history'):
                row = dindex[cohort, 'occupation_screen', f'occupation{j}', block]
                assert int(row['test_rc']) == 0
                assert float(row['N']) == float(sindex[cohort]['occupation'])
                assert float(row['clusters']) == float(sindex[cohort]['people_occ'])
    return cindex, dindex, sindex


def make_tables(cindex, dindex, sindex, timing):
    # Shared table content is rendered into PDF, LaTeX, and a machine readable audit.
    summary = {'title': 'Table 1. Predictive relevance of potential experience instruments',
               'subtitle': 'Baseline experience specification', 'panels': []}
    coefficients = {'title': 'Table 2. First stage coefficients on excluded instruments',
                    'subtitle': 'Coefficients with respondent clustered standard errors in parentheses', 'panels': []}
    occupation = {'title': 'Table 3. Occupation history prediction checks',
                  'subtitle': 'Supplementary evidence on predictive relevance', 'panels': []}
    for cohort in (0, 1):
        title = f"Panel {'A' if cohort == 0 else 'B'}. NLSY{79 if cohort == 0 else 97}"
        ds = [dindex[cohort, 'experience', y, 'all'] for y in DEPENDENTS]
        rows = []
        for label, field, digits in [('Joint F statistic', 'F', 2),
                                      ('Joint test p value', 'p', None),
                                      ('Partial R squared', 'partial_r2', 3),
                                      ('R squared', 'r2', 3),
                                      ('Observations', 'N', 0),
                                      ('Respondents', 'clusters', 0),
                                      ('Excluded instruments', 'excluded_count', 0)]:
            rows.append([label] + [pvalue(d[field]) if digits is None else fnum(d[field], digits) for d in ds])
        summary['panels'].append({'title': title, 'headers': ['Dependent variable'] + DEPENDENT_LABELS,
                                  'rows': rows, 'cohort': cohort})
        coef_rows = []
        for instrument, label in zip(INSTRUMENTS, INSTRUMENT_LABELS):
            row = [label]
            for dependent in DEPENDENTS:
                c = cindex[cohort, dependent, instrument]
                row.append({'b': fnum(c['b'], 4), 'se': fnum(c['se'], 4), 'stars': stars(c['p'])})
            coef_rows.append(row)
        coef_rows += [rows[0], rows[2], rows[4], rows[5]]
        coefficients['panels'].append({'title': title, 'headers': ['Excluded instrument'] + DEPENDENT_LABELS,
                                       'rows': coef_rows, 'cohort': cohort})
        occ_rows = []
        for j, label in enumerate(OCCUPATIONS, 1):
            a = dindex[cohort, 'occupation_screen', f'occupation{j}', 'all']
            h = dindex[cohort, 'occupation_screen', f'occupation{j}', 'history']
            occ_rows.append([label, fnum(h['F']), pvalue(h['p']), fnum(a['F']), fnum(a['partial_r2'], 3)])
        a = dindex[cohort, 'occupation_screen', 'occupation1', 'all']
        h = dindex[cohort, 'occupation_screen', 'occupation1', 'history']
        occupation['panels'].append({'title': title,
            'headers': ['Current occupation', 'History F', 'History p', 'Full set F', 'Full set partial R2'],
            'rows': occ_rows, 'cohort': cohort,
            'footer': (f"Observations: {fnum(a['N'], 0)}; respondents: {fnum(a['clusters'], 0)}; "
                       f"history indicators tested: {fnum(h['df_num'], 0)}; "
                       f"total excluded instruments: {fnum(a['excluded_count'], 0)}.")})
    controls = ('Every regression includes schooling, ASVAB, tenure through its cubic term, '
                'schooling times tenure, ASVAB times tenure, and indicators for year, sex, race, '
                'and original job number. Schooling, ASVAB, and tenure terms are treated as exogenous. '
                'Sampling weights are used and inference is clustered by respondent.')
    definitions = ('E denotes actual experience, P potential experience, S schooling, and A the ASVAB score. '
                   'Each column is a separate regression containing all five excluded instruments: '
                   'P, P squared, P cubed, S times P, and A times P.')
    sample = ('The sample retains original job numbers 1 to 3, NLSY79 observations through 2004, '
              'and all available NLSY97 years. Eligibility follows the existing pooled wage winsorization '
              'at the 1st and 99th percentiles. P is survey year less earliest recorded employment year; '
              'it includes nonemployment after entry. It is an observed entry proxy and may include student work. '
              'NLSY79 starts coded as week zero have unknown dates before 1978 and are left missing.')
    summary['notes'] = [definitions, controls, sample,
        (f"Requiring usable potential experience reduces the eligible NLSY79 sample from {fnum(sindex[0]['eligible'], 0)} "
         f"to {fnum(sindex[0]['experience'], 0)} observations, and NLSY97 from {fnum(sindex[1]['eligible'], 0)} "
         f"to {fnum(sindex[1]['experience'], 0)}. Partial R squared measures the additional explanatory power "
         'of the full excluded instrument set, conditional on the included controls. Joint F tests have '
         '5 numerator degrees of freedom and the number of respondents less one denominator degrees of freedom. '
         'These tests do not establish exclusion validity or conditional strength for the joint IV system.')]
    coefficients['notes'] = [definitions,
        'Estimates are reported in original units. Standard errors appear beneath coefficients. '
        '*** p < 0.01, ** p < 0.05, * p < 0.10. These stars concern individual coefficients, '
        'whereas the joint F statistic tests all five excluded instruments together.',
        controls, 'The samples and entry definition are identical to Table 1. '
        'Control coefficients are included in estimation and omitted from the display. '
        'No structural wage coefficients are estimated in these tables.']
    timing_note = ('Histories use the previous two scheduled survey waves, including biennial waves; '
                   'missing interviews are not skipped.') if timing == 'wave' else (
                   'Histories are restricted to gaps of exactly one and two calendar years.')
    occupation['notes'] = [
        'Each row is a linear probability regression for the indicated current occupation. '
        'Service is the omitted outcome category. Each regression includes the five potential experience '
        'terms and the same exogenous controls as Table 1, together with interactions between occupation '
        'indicators from the previous two survey waves. Only current main job rows with both lagged '
        'occupations observed are included. ' + timing_note,
        'One observed history pair is omitted with the intercept. '
        'Empty history pairs are excluded. History F tests only the occupation history block, conditional '
        'on the potential experience instruments and included controls. Full set F and partial R squared '
        'refer to all excluded instruments together. Standard errors are clustered by respondent and '
        'sampling weights are used. Joint test p values below 0.001 are displayed as <0.001.',
        'These are supplementary prediction checks. They do not implement the full transformed wage model '
        'or nonlinear IV estimation in Gibbons et al. (2005). The occupation interactions required by the '
        'full thesis wage model are not tested here, and relevance alone does not establish instrument validity.',
        'Presentation reference: Gibbons, Katz, Lemieux, and Parent (2005), Journal of Labor Economics, '
        '23(4), Table B3. DOI: 10.1086/491606. Formatting assistance: Codex; numerical estimates are read '
        'directly from the saved Stata exports.']
    return [summary, coefficients, occupation]


def render_pdf(tables, destination):
    styles = {
        'title': ParagraphStyle('title', fontName='Times-Bold', fontSize=13, leading=16, spaceAfter=5),
        'subtitle': ParagraphStyle('subtitle', fontName='Times-Italic', fontSize=10.5, leading=13, spaceAfter=12),
        'panel': ParagraphStyle('panel', fontName='Times-Bold', fontSize=10.5, leading=13, spaceAfter=5),
        'cell': ParagraphStyle('cell', fontName='Times-Roman', fontSize=10, leading=12, alignment=TA_RIGHT),
        'label': ParagraphStyle('label', fontName='Times-Roman', fontSize=10, leading=12, alignment=TA_LEFT),
        'header': ParagraphStyle('header', fontName='Times-Roman', fontSize=10, leading=12, alignment=TA_CENTER),
        'note': ParagraphStyle('note', fontName='Times-Roman', fontSize=9, leading=11, spaceAfter=5),
    }
    story = []
    for index, spec in enumerate(tables):
        if index:
            story.append(PageBreak())
        story.append(Paragraph(spec['title'], styles['title']))
        story.append(Paragraph(spec['subtitle'], styles['subtitle']))
        for panel in spec['panels']:
            story.append(Paragraph(panel['title'], styles['panel']))
            header = [Paragraph(math_label(h), styles['label' if j == 0 else 'header'])
                      for j, h in enumerate(panel['headers'])]
            matrix = [header]
            for row in panel['rows']:
                formatted = []
                for j, value in enumerate(row):
                    if isinstance(value, dict):
                        txt = (value['b'].replace('-', '−') + f"<super>{value['stars']}</super>"
                               + '<br/>(' + value['se'] + ')')
                    else:
                        txt = math_label(value) if j == 0 else html.escape(value)
                    formatted.append(Paragraph(txt, styles['label' if j == 0 else 'cell']))
                matrix.append(formatted)
            widths = [154, 92.5, 92.5, 92.5, 92.5] if index == 2 else [139] + [77] * 5
            table = Table(matrix, colWidths=widths, hAlign='LEFT', repeatRows=1)
            commands = [('VALIGN', (0, 0), (-1, -1), 'MIDDLE'),
                        ('LEFTPADDING', (0, 0), (-1, -1), 4),
                        ('RIGHTPADDING', (0, 0), (-1, -1), 4),
                        ('TOPPADDING', (0, 0), (-1, -1), 3),
                        ('BOTTOMPADDING', (0, 0), (-1, -1), 3),
                        ('LINEABOVE', (0, 0), (-1, 0), 0.8, colors.black),
                        ('LINEBELOW', (0, 0), (-1, 0), 0.45, colors.black),
                        ('LINEBELOW', (0, -1), (-1, -1), 0.8, colors.black)]
            if index == 1:
                commands += [('LINEABOVE', (0, 6), (-1, 6), 0.4, colors.black),
                             ('TOPPADDING', (0, 1), (-1, -1), 2),
                             ('BOTTOMPADDING', (0, 1), (-1, -1), 2)]
            table.setStyle(TableStyle(commands))
            story += [table, Spacer(1, 8)]
            if 'footer' in panel:
                story += [Paragraph(panel['footer'], styles['note']), Spacer(1, 7)]
            else:
                story.append(Spacer(1, 4))
        for i, note in enumerate(spec['notes']):
            prefix = '<b>Notes.</b> ' if i == 0 else ''
            story.append(Paragraph(prefix + html.escape(note), styles['note']))

    def footer(canvas, document):
        canvas.setFont('Times-Roman', 8)
        canvas.drawString(44, 27, 'NLSY first stage results | Prepared for discussion with Professor Smith')
        canvas.drawRightString(568, 27, str(document.page))

    doc = SimpleDocTemplate(str(destination), pagesize=letter, leftMargin=44, rightMargin=44,
                           topMargin=40, bottomMargin=43, title='NLSY first stage results',
                           author='Research tables from Stata estimates')
    doc.build(story, onFirstPage=footer, onLaterPages=footer)


def escape_tex(value):
    return value.replace('&', r'\&').replace('%', r'\%').replace('_', r'\_').replace('<', r'$<$').replace('>', r'$>$')


def latex_table(spec, index):
    lines = [r'\begin{center}', r'{\large\bfseries ' + escape_tex(spec['title']) + r'}\par',
             r'\smallskip', r'\textit{' + escape_tex(spec['subtitle']) + r'}\par',
             r'\medskip', r'\end{center}', r'\small']
    for panel in spec['panels']:
        lines += [r'\noindent\textbf{' + panel['title'] + r'}\par\smallskip',
                  r'\noindent\begin{tabular*}{\textwidth}{@{\extracolsep{\fill}}l' + 'r' * (len(panel['headers']) - 1) + r'@{}}',
                  r'\toprule']
        headers = [math_label(h, tex=True) for h in panel['headers']]
        if index == 2:
            headers[-1] = r'Full set partial $R^2$'
        lines += [' & '.join(headers) + r' \\', r'\midrule']
        for row_index, row in enumerate(panel['rows']):
            if isinstance(row[1], dict):
                estimates = [math_label(row[0], tex=True)]
                errors = ['']
                for cell in row[1:]:
                    suffix = '^{' + cell['stars'] + '}' if cell['stars'] else ''
                    estimates.append('$' + cell['b'] + suffix + '$')
                    errors.append('$(' + cell['se'] + ')$')
                lines += [' & '.join(estimates) + r' \\', ' & '.join(errors) + r' \\[2pt]']
            else:
                if index == 1 and row_index == 5:
                    lines.append(r'\midrule')
                cells = [math_label(str(row[0]), tex=True)] + [escape_tex(str(x)) for x in row[1:]]
                lines.append(' & '.join(cells) + r' \\')
        lines += [r'\bottomrule', r'\end{tabular*}\par\smallskip']
        if 'footer' in panel:
            lines.append(r'{\footnotesize ' + escape_tex(panel['footer']) + r'\par}')
        lines.append(r'\medskip')
    lines += [r'{\footnotesize', r'\noindent\textit{Notes.} ' + escape_tex(spec['notes'][0]) + r'\par']
    for note in spec['notes'][1:]:
        lines.append(r'\smallskip\noindent ' + escape_tex(note) + r'\par')
    lines.append('}')
    return '\n'.join(lines)


def main():
    results = Path(sys.argv[1]).resolve()
    timing = sys.argv[2] if len(sys.argv) > 2 else results.name
    assert timing in ('wave', 'annual')
    output = Path(sys.argv[3]).resolve() if len(sys.argv) > 3 else results
    output.mkdir(parents=True, exist_ok=True)
    cindex, dindex, sindex = load_and_check(results)
    tables = make_tables(cindex, dindex, sindex, timing)
    render_pdf(tables, output / 'firststage_tables.pdf')
    fragments = [latex_table(spec, i) for i, spec in enumerate(tables)]
    for name, text in zip(['table_firststage_diagnostics', 'table_firststage_coefficients',
                           'table_occupation_screen'], fragments):
        (output / (name + '.tex')).write_text(text + '\n')
    preamble = r'''\documentclass[10pt,letterpaper]{article}
\usepackage[margin=0.6in]{geometry}
\usepackage{booktabs,amsmath,array}
\usepackage[T1]{fontenc}
\setlength{\parindent}{0pt}
\setlength{\tabcolsep}{4pt}
\renewcommand{\arraystretch}{1.08}
\begin{document}
'''
    (output / 'firststage_tables.tex').write_text(
        preamble + ('\n' + r'\newpage' + '\n').join(fragments)
        + '\n' + r'\end{document}' + '\n')
    audit = {'history_timing': timing,
             'source_hashes': {name: hashlib.sha256((results / name).read_bytes()).hexdigest()
                               for name in ['coefficients.csv', 'diagnostics.csv', 'samples.csv']},
             'presentation_reference': PAPER, 'tables': tables}
    (output / 'table_values.json').write_text(json.dumps(audit, indent=2))
    (output / 'table_export_success.txt').write_text('All input identities checked; PDF and LaTeX tables exported.\n')
    print(f'Exported firststage_tables.pdf, complete LaTeX, and three table fragments to {output}')


if __name__ == '__main__':
    main()
