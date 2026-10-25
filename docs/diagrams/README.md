# Core Banking Chen ER model

The model follows `sql/01_ddl.sql`: twelve entities, eleven declared parent-child
relationships, and eighty-one physical columns. `Audit_Log` has no FK. There is
no declared Branch-to-Bank_Directory or Beneficiary-to-Account relationship.

`chen-overview.png` is the complete relationship overview. The other four PNGs
show all attributes, grouped for readability in the reports. Rectangles denote
entities, diamonds relationships and ellipses attributes. Primary keys are
underlined; `EMI_Amount` and `MaturityAmount` have dashed ellipses. The 1:N edge
labels express maximum cardinality; child references are mandatory and parents
may have zero children. The complete physical FK columns appear in the attribute
panels as well as the conceptual relationships in the overview.

Each PNG was rendered and downloaded in the browser using Mermaid 12.2.0.
The `.mmd` files remain editable Mermaid flowcharts; `.svg` exports preserve the
final native ellipse outlines and underlining. Mermaid's stadium layout is
converted to true SVG ellipses by the local renderer, so Chen attributes are
ovals rather than flowchart pills. This is not Mermaid's crow's-foot `erDiagram`
syntax. No AI image generation or database modification is involved.

To regenerate sources and prepare a local browser preview from the project root:

```powershell
uv run python build_chen_diagrams.py
npm install --prefix .report_work/mermaid-renderer mermaid@12.2.0
New-Item -ItemType Directory -Force frontend/public/report-diagrams
Copy-Item docs/diagrams/renderer.html frontend/public/report-diagrams/index.html
Copy-Item docs/diagrams/diagrams.json frontend/public/report-diagrams/diagrams.json
Copy-Item .report_work/mermaid-renderer/node_modules/mermaid/dist frontend/public/report-diagrams/vendor -Recurse -Force
```

With Vite running, open `http://localhost:5173/report-diagrams/index.html` and
download each panel. Keep the exported PNG filenames in this directory before
regenerating the reports. The temporary preview/vendor directory is gitignored;
Mermaid is not added to the banking application's production dependencies.
