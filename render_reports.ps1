param(
    [ValidateSet(2,3)] [int] $Review = 2,
    [string] $OutputDirectory = '.report_work\render-v1',
    [string] $SourcePath = ''
)
# Read-only native Word pagination; no desktop LibreOffice dependency.
# The report files are not saved or rewritten by Word.
$ErrorActionPreference = 'Stop'
$reportRoot = $PSScriptRoot
$reportOutput = [System.IO.Path]::GetFullPath((Join-Path $reportRoot $OutputDirectory))
New-Item -ItemType Directory -Path $reportOutput -Force | Out-Null
$reportWord = New-Object -ComObject Word.Application
$reportWord.Visible = $false
$reportWord.DisplayAlerts = 0
try {
    $reportSource = if ($SourcePath) { [System.IO.Path]::GetFullPath((Join-Path $reportRoot $SourcePath)) } else { Join-Path $reportRoot "Project Template - review $Review.docx" }
    $reportDoc = $reportWord.Documents.Open($reportSource, $false, $true)
    $reportDoc.ExportAsFixedFormat((Join-Path $reportOutput "review$Review.pdf"), 17)
    Write-Output "Rendered Review $Review to $reportOutput"
} finally {
    try { $reportDoc.Close(0) } catch {}
    try { $reportWord.Quit() } catch {}
}
