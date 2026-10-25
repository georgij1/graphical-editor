$out = @()
$w = New-Object -ComObject Word.Application
$w.Visible = $false; $w.DisplayAlerts = 0
try {
  $d = $w.Documents.Open('C:\Users\Panov\AppData\Local\Temp\opencode\kr\staging_ascii.docx', $false, $true)
  $d.Repaginate()
  $out += "PAGES=" + $d.ComputeStatistics(2)
  $out += "TABLES=" + $d.Tables.Count
  $out += "PICS=" + $d.InlineShapes.Count
  $out += "FOOTNOTES=" + $d.Footnotes.Count
  foreach ($p in $d.Paragraphs) {
    $t = ($p.Range.Text -replace "[`r`n`v`f`t]+$", "")
    if ($p.Format.OutlineLevel -eq 1 -and $t.Length -gt 0) { $out += ($t + " = " + $p.Range.Information(3)) }
  }
  $d.Close(0)
} catch { $out += "ERR: " + $_.Exception.Message }
$w.Quit()
$out | Out-File -FilePath 'C:\Users\Panov\AppData\Local\Temp\opencode\kr\tcheck.log' -Encoding utf8