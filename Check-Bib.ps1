```powershell
param(
    [Parameter(Mandatory = $true)]
    [string]$BibFile
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $BibFile)) {
    throw "File not found: $BibFile"
}

$BibFile = (Resolve-Path $BibFile).Path
$BaseDir = Split-Path $BibFile
$BaseName = [System.IO.Path]::GetFileNameWithoutExtension($BibFile)

$AuditDir = Join-Path $BaseDir "${BaseName}-audit"

if (Test-Path $AuditDir) {
    Remove-Item $AuditDir -Recurse -Force
}
New-Item -ItemType Directory -Path $AuditDir | Out-Null

$LogFile = Join-Path $AuditDir "biber.log"
$ReportFile = Join-Path $AuditDir "report.txt"

"Bibliography audit" | Set-Content $ReportFile
"File: $BibFile" | Add-Content $ReportFile
"Date: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Add-Content $ReportFile
"" | Add-Content $ReportFile

Write-Host "Checking that Biber is available..."

try {
    $BiberVersion = & biber --version 2>&1
    $BiberVersion | Add-Content $ReportFile
}
catch {
    throw "Biber is not available in PATH."
}

Write-Host "Running Biber validation..."

Push-Location $AuditDir

try {
    & biber `
        --tool `
        --validate-datamodel `
        --output-format=bibtex `
        --output-file="${BaseName}-cleaned.bib" `
        $BibFile 2>&1 |
        Tee-Object -FilePath $LogFile
}
finally {
    Pop-Location
}

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"BIBER WARNINGS AND ERRORS" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

Select-String `
    -Path $LogFile `
    -Pattern "WARN|ERROR|FATAL" |
    ForEach-Object {
        $_.Line
    } |
    Add-Content $ReportFile


# ------------------------------------------------------------
# Read complete bibliography
# ------------------------------------------------------------

$Text = Get-Content $BibFile -Raw


# ------------------------------------------------------------
# Duplicate citation keys
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"DUPLICATE CITATION KEYS" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

$KeyMatches = [regex]::Matches(
    $Text,
    '(?im)^\s*@\w+\s*[\{\(]\s*([^,\s]+)\s*,'
)

$Keys = foreach ($Match in $KeyMatches) {
    $Match.Groups[1].Value
}

$Duplicates = $Keys |
    Group-Object |
    Where-Object { $_.Count -gt 1 } |
    Sort-Object Name

if ($Duplicates) {
    foreach ($D in $Duplicates) {
        "DUPLICATE: $($D.Name)  count=$($D.Count)" |
            Add-Content $ReportFile
    }
}
else {
    "No duplicate citation keys found." |
        Add-Content $ReportFile
}


# ------------------------------------------------------------
# Entries containing both date and year
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"ENTRIES CONTAINING BOTH DATE AND YEAR" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

$EntryMatches = [regex]::Matches(
    $Text,
    '(?ms)@\w+\s*[\{\(]\s*([^,\s]+)\s*,(.*?)(?=^\s*@|\z)'
)

$DateYearCount = 0

foreach ($Entry in $EntryMatches) {

    $Key  = $Entry.Groups[1].Value
    $Body = $Entry.Groups[2].Value

    $HasDate = $Body -match '(?im)^\s*date\s*='
    $HasYear = $Body -match '(?im)^\s*year\s*='

    if ($HasDate -and $HasYear) {
        $DateYearCount++
        "DATE+YEAR: $Key" | Add-Content $ReportFile
    }
}

if ($DateYearCount -eq 0) {
    "No entries contain both date and year." |
        Add-Content $ReportFile
}


# ------------------------------------------------------------
# Suspicious DOI values
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"SUSPICIOUS DOI FIELDS" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

$BadDoiCount = 0

foreach ($Entry in $EntryMatches) {

    $Key  = $Entry.Groups[1].Value
    $Body = $Entry.Groups[2].Value

    $DoiMatch = [regex]::Match(
        $Body,
        '(?im)^\s*doi\s*=\s*[\{"]([^}"]+)[}"]'
    )

    if ($DoiMatch.Success) {

        $Doi = $DoiMatch.Groups[1].Value.Trim()

        if ($Doi -notmatch '^10\.\d{4,9}/\S+$') {
            $BadDoiCount++
            "SUSPICIOUS DOI: $Key"
            "    $Doi"
            "" |
                Add-Content $ReportFile
        }
    }
}

if ($BadDoiCount -eq 0) {
    "No obviously malformed DOI fields found." |
        Add-Content $ReportFile
}


# ------------------------------------------------------------
# DOI fields containing URL prefixes
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"DOI FIELDS CONTAINING URL PREFIXES" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

$DoiUrlCount = 0

foreach ($Entry in $EntryMatches) {

    $Key  = $Entry.Groups[1].Value
    $Body = $Entry.Groups[2].Value

    $DoiMatch = [regex]::Match(
        $Body,
        '(?im)^\s*doi\s*=\s*[\{"]([^}"]+)[}"]'
    )

    if ($DoiMatch.Success) {

        $Doi = $DoiMatch.Groups[1].Value.Trim()

        if ($Doi -match '^https?://(dx\.)?doi\.org/') {
            $DoiUrlCount++
            "DOI URL PREFIX: $Key"
            "    $Doi"
            "" |
                Add-Content $ReportFile
        }
    }
}

if ($DoiUrlCount -eq 0) {
    "No DOI URL prefixes found." |
        Add-Content $ReportFile
}


# ------------------------------------------------------------
# Suspicious URL values
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"SUSPICIOUS URL FIELDS" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

foreach ($Entry in $EntryMatches) {

    $Key  = $Entry.Groups[1].Value
    $Body = $Entry.Groups[2].Value

    $UrlMatch = [regex]::Match(
        $Body,
        '(?im)^\s*url\s*=\s*[\{"]([^}"]+)[}"]'
    )

    if ($UrlMatch.Success) {

        $Url = $UrlMatch.Groups[1].Value.Trim()

        if ($Url -notmatch '^https?://') {
            "SUSPICIOUS URL: $Key"
            "    $Url"
            "" |
                Add-Content $ReportFile
        }
    }
}


# ------------------------------------------------------------
# Missing title
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"ENTRIES WITHOUT TITLE" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

foreach ($Entry in $EntryMatches) {

    $Key  = $Entry.Groups[1].Value
    $Body = $Entry.Groups[2].Value

    if ($Body -notmatch '(?im)^\s*title\s*=') {
        "NO TITLE: $Key" | Add-Content $ReportFile
    }
}


# ------------------------------------------------------------
# Empty fields
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"EMPTY FIELDS" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

$EmptyFields = [regex]::Matches(
    $Text,
    '(?im)^\s*(\w+)\s*=\s*(?:\{\s*\}|""),?'
)

if ($EmptyFields.Count -eq 0) {
    "No empty fields found." | Add-Content $ReportFile
}
else {
    foreach ($M in $EmptyFields) {
        "EMPTY FIELD: $($M.Groups[1].Value)" |
            Add-Content $ReportFile
    }
}


# ------------------------------------------------------------
# Summary
# ------------------------------------------------------------

"" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile
"SUMMARY" | Add-Content $ReportFile
"============================================================" | Add-Content $ReportFile

"Entries:              $($Keys.Count)" | Add-Content $ReportFile
"Duplicate keys:       $($Duplicates.Count)" | Add-Content $ReportFile
"date + year entries:  $DateYearCount" | Add-Content $ReportFile
"Suspicious DOI:       $BadDoiCount" | Add-Content $ReportFile
"DOI URL prefixes:     $DoiUrlCount" | Add-Content $ReportFile

"" | Add-Content $ReportFile
"Generated cleaned bibliography:" | Add-Content $ReportFile
"    $(Join-Path $AuditDir "${BaseName}-cleaned.bib")" |
    Add-Content $ReportFile

Write-Host ""
Write-Host "Audit complete."
Write-Host "Report:"
Write-Host "  $ReportFile"
Write-Host ""
Write-Host "Biber log:"
Write-Host "  $LogFile"
Write-Host ""
Write-Host "Biber-normalized bibliography:"
Write-Host "  $(Join-Path $AuditDir "${BaseName}-cleaned.bib")"
```