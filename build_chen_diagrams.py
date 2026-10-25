"""Build editable Mermaid Chen diagrams from the project's actual DDL.

Serve docs/diagrams/renderer.html through the Vite public preview to render
and download the PNGs (see docs/diagrams/README.md). No database connection or
data mutation is required.
"""
from pathlib import Path
import json
import re

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'docs' / 'diagrams'
OUT.mkdir(parents=True, exist_ok=True)
ddl = (ROOT / 'sql' / '01_ddl.sql').read_text(encoding='utf-8')
tables = {}
relationships = []
for match in re.finditer(r'CREATE TABLE (\w+) \((.*?)\n\);', ddl, re.S):
    name, body = match.groups()
    columns = []
    for line in body.splitlines():
        column = re.match(r'    (\w+)\s+(VARCHAR|INT|BIGINT|SERIAL|DECIMAL|TEXT|DATE|TIMESTAMP)\b(.*)', line)
        if not column:
            continue
        field, kind, tail = column.groups()
        fk = re.search(r'REFERENCES (\w+)\((\w+)\)', tail)
        columns.append({'name': field, 'primary': 'PRIMARY KEY' in tail,
                        'foreign': bool(fk), 'derived': 'GENERATED ALWAYS' in tail})
        if fk:
            relationships.append({'parent': fk[1], 'child': name,
                                  'foreign_key': field, 'parent_key': fk[2]})
    tables[name] = columns
assert len(tables) == 12 and len(relationships) == 11
labels = {
    ('Postal_Directory', 'Branch'): 'Locates',
    ('Customer', 'Account'): 'Owns',
    ('Branch', 'Account'): 'Maintains',
    ('Account', 'Transaction_History'): 'Records',
    ('Customer', 'Loan'): 'Borrows',
    ('Branch', 'Loan'): 'Issues',
    ('Loan', 'Loan_Repayment'): 'Receives',
    ('Customer', 'Beneficiary'): 'Registers',
    ('Bank_Directory', 'Beneficiary'): 'Resolves bank',
    ('Customer', 'Fixed_Deposit'): 'Invests in',
    ('Branch', 'Employee'): 'Employs',
}
STYLE = '''
classDef entity fill:#e8f0fc,stroke:#163865,stroke-width:2px,color:#12223b,font-weight:bold;
classDef relationship fill:#fff8e7,stroke:#8c6720,stroke-width:1.7px,color:#3e3216;
classDef attribute fill:#ffffff,stroke:#4b617a,stroke-width:1.4px,color:#172b43;
classDef derived fill:#ffffff,stroke:#4b617a,stroke-width:1.6px,stroke-dasharray:6 4,color:#172b43;
linkStyle default stroke:#52657c,stroke-width:1.5px;
'''


def attribute(node, item):
    label = item['name'] + (' (FK)' if item['foreign'] else '')
    line = f'{node}(["{label}"]):::' + ('derived' if item['derived'] else 'attribute')
    return line + (f'\nclass {node} primary;' if item['primary'] else '')


panels = []
overview = ['flowchart TB']
for name in tables:
    overview.append(f'{name}["{name}"]:::entity')
for i, rel in enumerate(relationships):
    overview += [f'r{i}{{"{labels[(rel["parent"], rel["child"])]}"}}:::relationship',
                 f'{rel["parent"]} ---|"1"| r{i}',
                 f'r{i} ---|"N"| {rel["child"]}']
for table, field in [('Loan', 'EMI_Amount'), ('Fixed_Deposit', 'MaturityAmount')]:
    overview += [attribute(field, {'name': field, 'derived': True, 'primary': False, 'foreign': False}),
                 f'{table} --- {field}']
# Audit_Log has no declared FK. A disconnected node is intentional.
overview += [STYLE]
panels.append({'id': 'chen-overview', 'title': 'Twelve entity relationship overview',
               'note': 'Rectangles are entities; diamonds are relationships; dashed ovals are derived attributes. 1:N gives maximum cardinality. Every child FK is mandatory; a parent may have zero or many children. Audit_Log is independent.',
               'mermaid': '\n'.join(overview)})
groups = [
    ('chen-identity', 'Customer accounts and transaction attributes', ['Customer', 'Account', 'Transaction_History']),
    ('chen-credit', 'Loan repayment and fixed deposit attributes', ['Loan', 'Loan_Repayment', 'Fixed_Deposit']),
    ('chen-network', 'Branch employee and postal attributes', ['Branch', 'Employee', 'Postal_Directory']),
    ('chen-payees-audit', 'Beneficiary bank directory and audit attributes', ['Beneficiary', 'Bank_Directory', 'Audit_Log']),
]
for panel_id, title, names in groups:
    lines = ['flowchart TB']
    for i, name in enumerate(names):
        lines += [f'subgraph group{i}[" "]', 'direction LR', f'{name}["{name}"]:::entity']
        for n, field in enumerate(tables[name]):
            node = f'{name}_a{n}'
            lines += [attribute(node, field), f'{name} --- {node}']
        lines += ['end', f'style group{i} fill:#ffffff,stroke:#ffffff;']
    lines += [STYLE]
    panels.append({'id': panel_id, 'title': title,
                   'note': 'Underlined oval labels are primary keys. FK identifies a physical foreign-key column; corresponding relationships are in the overview. Dashed ovals are generated derived values. All remaining columns appear as ordinary attribute ovals.',
                   'mermaid': '\n'.join(lines)})
for panel in panels:
    (OUT / (panel['id'] + '.mmd')).write_text(panel['mermaid'], encoding='utf-8')
(OUT / 'diagrams.json').write_text(json.dumps(panels, indent=2), encoding='utf-8')
(OUT / 'schema_manifest.json').write_text(json.dumps({'tables': tables, 'relationships': relationships}, indent=2), encoding='utf-8')
print(f'Built {len(panels)} Mermaid panels: 12 entities, 11 relationships, {sum(map(len,tables.values()))} attributes.')
