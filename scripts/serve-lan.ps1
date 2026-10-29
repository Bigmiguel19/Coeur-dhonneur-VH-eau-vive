$r = Split-Path -Parent $PSScriptRoot
$p = 5174
$m = @{".html"="text/html; charset=utf-8";".css"="text/css; charset=utf-8";".js"="text/javascript; charset=utf-8";".svg"="image/svg+xml";".png"="image/png";".ico"="image/x-icon"}
$l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $p)
$l.Start()
$n = ([char]13).ToString() + ([char]10).ToString()
Write-Host "Serveur LAN actif sur le port $p"
while ($true) {
  $c = $l.AcceptTcpClient()
  try {
    $s = $c.GetStream()
    $ln = (New-Object System.IO.StreamReader($s)).ReadLine()
    if ($ln) {
      $q = $ln.Split([char]32)[1].Split([char]63)[0].Trim([char]47)
      if (-not $q) { $q = "index.html" }
      $f = Join-Path $r $q
      if (Test-Path $f -PathType Leaf) {
        $b = [System.IO.File]::ReadAllBytes($f)
        $t = $m[[System.IO.Path]::GetExtension($f).ToLower()]
        if (-not $t) { $t = "application/octet-stream" }
        $h = "HTTP/1.1 200 OK" + $n + "Content-Type: " + $t + $n + "Content-Length: " + $b.Length + $n + "Connection: close" + $n + $n
      } else {
        $b = [System.Text.Encoding]::UTF8.GetBytes("404")
        $h = "HTTP/1.1 404 Not Found" + $n + "Content-Length: 3" + $n + "Connection: close" + $n + $n
      }
      $hb = [System.Text.Encoding]::ASCII.GetBytes($h)
      $s.Write($hb, 0, $hb.Length)
      $s.Write($b, 0, $b.Length)
      $s.Flush()
    }
  } catch { }
  $c.Close()
}
