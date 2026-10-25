# DBMS review reports

## Current synchronized reports

Review 2 now mirrors the finalized Review 3 content through Section 8.8.
All 586 shared body blocks, including the user's Section 6 revisions, diagrams,
SQL, refined explanations and screenshots, match the source XML exactly. It has
73 displayed images and renders to 98 pages. Its cover, scoped contribution
table and original faculty assessment remain appropriate to Review 2. The old
checklist, dated capture captions and duplicated written output are removed.
Review 3-only concurrency, tests and application pages remain outside Review 2.

Review 3 and Guide are byte-for-byte unchanged by this synchronization. The
before-copy, finalized source snapshot, comparison audit, refreshed contents-page
map and rendered validation are in `.report_work/review2-final-sync/`. The helper
`.report_work/sync_review2_from_review3.py` copies finalized blocks rather than
restoring content from old report templates. The earlier notes below describe
the preceding editing stages.

## Current Review 3 editing authority

On 2026-10-20 the owner manually deleted material from Review 3 and confirmed
those deletions as final. The current root Review 3 DOCX is now the authority.
Do not regenerate Review 3 from `generate_reports.py` without first reconciling
those manual edits: the original-template builder would restore deleted content.
The latest refinement uses `refine_review3.py` to patch only document.xml in the
current file, preserving all other package parts and every image. It removes
dated screenshot-caption suffixes and duplicated typed output previews, while
retaining predictions and required row-count, test and security evidence.
Review 2 remained unchanged at this stage; it is now synchronized as noted above.
The pre-refinement user version is retained in
`report_backups/before_review3_output_cleanup/`.

The later Review 3 reorganization preserves the current manual edits and all
102 displayed images. Section 8 now ends with 8.9 Concurrency and Locking
Demonstration and 8.10 Testing and Validation. Section 9 is Application
Screenshots and Section 10 is Work Breakdown. The standalone Review Requirements
section and completion checklist have moved out of the report. `Guide.docx`
contains the completion checklist, faculty reference requirements, demonstration
runbook and all 31 existing project-specific viva answers. Review 2 is unchanged.
The pre-reorganization version is in
`report_backups/before_review3_reorganization/`; the targeted operation and
preservation assertions are in `reorganize_review3.py` and
`.report_work/review3-reorganization/audit.json`.

The two root Word reports are populated in place. Their original templates are
retained, unchanged, in `report_backups/original/`. The VIT cover image binaries,
headers, footers, page geometry and final faculty grading grids are preserved.
The grading score cells remain blank for the evaluator.

The current rendered Review 3 contains 116 pages and its separate guide has six
pages. The earlier Review 2 render contains 104 pages; that file is unchanged.

Review 3 now includes six supplemental DBeaver captures in
`report_screenshots/review3/supplemental/`: a committed transfer and its history
and audits, a nonzero savings-interest credit, an FD maturity payout, and both
index-comparison plans. These examples use `banking_report_demo`, copied from
the installed live database with dedicated fixtures. Fingerprints verify that
all twelve live `banking_db` tables remain unchanged. Batch reruns were also
verified to create no duplicate postings. The supplemental SQL and manifest
remain beside the captures so the evidence can be reproduced.

`finalize_review3_evidence.py` patches the current report rather than rebuilding
it. It removes written capture timestamps, repeated Result Code payloads, the
extra view-updatability output table, and the test matrix's repeated actual-output
column. Predictions, SQL definitions, the 15-case matrix and all test screenshots
remain. The two old zero-posting batch pictures and old index picture are replaced;
105 images are displayed in the updated report. Review 2 and Guide are unchanged.
Preservation and database checks are in `.report_work/review3-final-evidence/`.
Both include the schema and all 35 standard and 10 business query statements
with live result samples, database objects, security evidence, three indexes,
query plans and the prescribed contribution allocation. Review 3 adds all 15
passing verification cases, concurrency, the six-step runbook, 13 dashboard tabs,
login/switching and project-specific viva preparation.

Review 3 now embeds 76 genuine DBeaver captures and 16 website captures from
2026-10-19, including all 35 standard queries, all 10 business queries, all 15
guarded tests, object demonstrations, RBAC, locking and the customer/staff tabs.
SQL and results/notices share each database capture; long content is a viewport
preview, accompanied by the report's complete SQL and result samples. The
existing schema is shown through live metadata instead of destructive recreation.
Raw PNGs and provenance manifests are in `report_screenshots/review3/`.
Review 2 now reuses 61 of the captured DBeaver screenshots for its shared
database sections and uses the same verified data snapshot as Review 3.
The later Review 2 update leaves the completed Review 3 byte-for-byte unchanged.

Both reports now also contain the browser-rendered Chen model in Section 5:
one relationship overview and four attribute panels covering all 12 entities,
11 declared foreign keys and 81 columns. Primary keys are underlined; generated
EMI and maturity amounts use dashed ovals. The editable Mermaid, SVG and PNG
files are retained in `docs/diagrams/`. This later ER update changes both reports;
it does not change the Category F queries or their disclosed count.

## Regeneration

```powershell
uv run python generate_reports.py
# Capture fresh evidence and regenerate when the database changes:
uv run python generate_reports.py --refresh-evidence
# Rebuild only the screenshot-enriched Review 3, retaining Review 2 unchanged:
uv run python generate_reports.py --review 3 --evidence .report_work/review3_screenshot_evidence.json
# Rebuild only Review 2 with the same shared evidence and database screenshots:
uv run python generate_reports.py --review 2 --evidence .report_work/review3_screenshot_evidence.json
```

`collect_report_evidence.py` reads the seven SQL files and collects results into
`.report_work/evidence.json`. The shared query/count snapshot is repeatable-read.
Subsequent live object demonstrations carry a separate timestamp because normal
presenter activity can change balances between captures. Live modifying proofs
are rolled back. The explicit-COMMIT transfer's successful path is exercised in
a disposable database; its insufficient-funds path is also verified on
`banking_db`. The collector never executes the destructive DDL against
`banking_db`, resets shared roles, or leaves test business rows behind. SERIAL
sequences can consume values despite rollback.

The generator uses python-docx and always starts from the retained originals.
It reuses an existing `.report_work/page_map.json` for the static contents pages.
After a content/evidence change, render and verify pagination before publishing;
the cached map can be supplied explicitly with `--page-map FILE`.

```powershell
# Windows read-only PDF quality check using installed Microsoft Word:
.\render_reports.ps1 -Review 2 -OutputDirectory '.report_work\new-render'
.\render_reports.ps1 -Review 3 -OutputDirectory '.report_work\new-render'
```

The Word renderer does not save or rewrite the DOCX files. The final reports
were also rasterized and inspected, with all-page text-boundary checks finding
no out-of-bounds body words. Rendered PDFs/PNGs are local QA intermediates.

## Remaining manual exhibits and rubric decisions

- The user subsequently authorized diagram generation. Both Chen ER slots are
  now filled; neither report has remaining screenshot or ER placeholders.
- Both reports' database screenshot slots have been filled with real captures.
  Review 3 also includes its final application modules and website screenshots.
- Category F implements all required functions in four statements, meeting the
  teacher-confirmed range of four to six. The complete catalogue stays at exactly
  35 queries; there is no Category F count discrepancy.
- Generated stored EMI and maturity values are described precisely as controlled
  derived extensions of normalized base facts; the formal strict-3NF caveat in
  PROJECT_SPEC.md is retained.

Portal identity selection is simulated, and the local API connects as postgres.
The reports distinguish database RBAC from unimplemented authenticated,
branch-scoped API authorization and real payment-rail settlement.

## Review 3 prose revision with Walter

The current Review 3 includes 42 reviewed explanatory-paragraph revisions from
five Walter website batches. Actual subscription debit was 2,010 words, from
19,047 to 17,037 remaining, within the user's 5,000-word ceiling. Raw drafts were
checked against the original and corrected where they altered counts,
identifiers, join behavior, transaction semantics or limitations.

The before-copy, batch usage ledger, reviewed replacements and validation audit
are retained in `.report_work/walter-prose/`. SQL paragraphs, expected-output
rows, formal normalization details, screenshots and all non-document XML package
parts are preserved. Review 2 and Guide hashes remain unchanged. Native Word
rendering remains 116 pages; contents-page references and page bounds were
verified, with visual review of the rendered report. Do not regenerate the
current report from the old templates; patch the current document in place.
