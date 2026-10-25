try {
  $w = New-Object -ComObject Word.Application
  $w.Visible = $false; $w.DisplayAlerts = 0
  $d = $w.Documents.Open('C:\Users\Panov\AppData\Local\Temp\opencode\kr\staging_ascii.docx', $false, $false)
  foreach ($toc in $d.TablesOfContents) { $toc.Update() }
  $d.Repaginate()
  "PAGES=" + $d.ComputeStatistics(2)
  $d.Close(0); $w.Quit()
} catch { "ERR: " + $_.Exception.Message }