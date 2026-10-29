<#
.SYNOPSIS
  Serveur de développement local pour Cœur d'Honneur.

.DESCRIPTION
  Sert le dossier du projet en HTTP sur http://localhost:<Port>/.
  Nécessaire car les modules JavaScript ES ne fonctionnent pas via file://.

  Aucune dépendance : PowerShell et .NET suffisent. Node.js n'est pas requis.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\serve.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\serve.ps1 -Port 8080
#>
param(
  [int]$Port = 5173,
  [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = "Stop"

$mime = @{
  ".html" = "text/html; charset=utf-8"
  ".css"  = "text/css; charset=utf-8"
  ".js"   = "text/javascript; charset=utf-8"
  ".mjs"  = "text/javascript; charset=utf-8"
  ".json" = "application/json; charset=utf-8"
  ".svg"  = "image/svg+xml"
  ".png"  = "image/png"
  ".jpg"  = "image/jpeg"
  ".jpeg" = "image/jpeg"
  ".webp" = "image/webp"
  ".ico"  = "image/x-icon"
  ".woff" = "font/woff"
  ".woff2"= "font/woff2"
  ".txt"  = "text/plain; charset=utf-8"
  ".map"  = "application/json; charset=utf-8"
}

$listener = New-Object System.Net.HttpListener
$prefix = "http://localhost:$Port/"
try {
  $listener.Prefixes.Add($prefix)
  $listener.Start()
}
catch {
  Write-Host "Impossible de demarrer le serveur sur $prefix" -ForegroundColor Red
  Write-Host "Cause probable : le port est deja utilise, ou une reservation d'URL est necessaire." -ForegroundColor Yellow
  Write-Host "Essayez un autre port : -Port 8080" -ForegroundColor Yellow
  exit 1
}

Write-Host ""
Write-Host "  Coeur d'Honneur - serveur de developpement" -ForegroundColor Green
Write-Host "  Racine : $Root"
Write-Host "  Adresse : http://localhost:$Port/"
Write-Host "  Arreter : Ctrl+C"
Write-Host ""

try {
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $request = $context.Request
    $response = $context.Response

    try {
      $relative = [System.Uri]::UnescapeDataString($request.Url.AbsolutePath.TrimStart("/"))
      if ([string]::IsNullOrWhiteSpace($relative)) { $relative = "index.html" }

      $full = Join-Path $Root $relative
      $full = [System.IO.Path]::GetFullPath($full)

      # Interdit toute sortie du dossier racine
      if (-not $full.StartsWith([System.IO.Path]::GetFullPath($Root), [StringComparison]::OrdinalIgnoreCase)) {
        $response.StatusCode = 403
        $response.Close()
        continue
      }

      if (Test-Path $full -PathType Container) {
        $full = Join-Path $full "index.html"
      }

      if (-not (Test-Path $full -PathType Leaf)) {
        $response.StatusCode = 404
        $body = [System.Text.Encoding]::UTF8.GetBytes("404 - Fichier introuvable")
        $response.ContentType = "text/plain; charset=utf-8"
        $response.OutputStream.Write($body, 0, $body.Length)
        $response.Close()
        continue
      }

      $extension = [System.IO.Path]::GetExtension($full).ToLowerInvariant()
      $contentType = $mime[$extension]
      if (-not $contentType) { $contentType = "application/octet-stream" }

      $bytes = [System.IO.File]::ReadAllBytes($full)

      $response.ContentType = $contentType
      $response.Headers.Add("Cache-Control", "no-store")
      $response.ContentLength64 = $bytes.Length
      $response.OutputStream.Write($bytes, 0, $bytes.Length)
      $response.Close()

      Write-Host ("  {0,-4} {1}" -f $request.HttpMethod, "/$relative") -ForegroundColor DarkGray
    }
    catch {
      try { $response.StatusCode = 500; $response.Close() } catch { }
    }
  }
}
finally {
  $listener.Stop()
  $listener.Close()
}
