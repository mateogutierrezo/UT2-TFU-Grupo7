<#
.DESCRIPTION
  Ejecuta contra el balanceador (Nginx, puerto 8080) las 6 pruebas documentadas
  en el informe y verifica automaticamente los codigos HTTP, la instancia que
  responde y el estado de los contenedores. Toda la salida se guarda en un
  archivo de evidencia (transcripcion de PowerShell).

  Pruebas:
    1. Ambas replicas sanas
    2. /api/health y /api/health/live accesibles sin JWT
    3. Base de datos no disponible en api-1 (FORCE_DB_FAIL)
    4. Restauracion de api-1
    5. api-1 detenida
    6. Ambas replicas detenidas (error controlado)

  El script debe estar en la carpeta scripts/ del repositorio: se posiciona
  solo en la raiz (donde esta docker-compose.yaml).

.PARAMETER BaseUrl
  URL del balanceador. Por defecto http://localhost:8080

.PARAMETER EvidenceFile
  Archivo donde se guarda la evidencia. Por defecto lleva fecha y hora, para
  no pisar evidencias anteriores.

.PARAMETER Clean
  Ejecuta "docker compose down -v" y reconstruye las imagenes antes de probar.
  Borra el volumen dbdata.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\test-health.ps1 -Clean
#>
param(
    [string]$BaseUrl = "http://localhost:8080",
    [string]$EvidenceFile = ("evidencia-health-{0}.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss")),
    [switch]$Clean
)

$ErrorActionPreference = "Continue"
Set-Location (Split-Path -Parent $PSScriptRoot)

$results = New-Object System.Collections.ArrayList
$aborted = $false
$api1Forced = $false
$failures = 0

# ---------------------------------------------------------------- utilidades

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host ("=== " + $Title + " ===") -ForegroundColor Cyan
}

function Add-Result {
    param([string]$Test, [bool]$Ok, [string]$Detail)
    $status = "FAIL"
    $color = "Red"
    if ($Ok) { $status = "PASS"; $color = "Green" }
    Write-Host ("  [{0}] {1}" -f $status, $Detail) -ForegroundColor $color
    [void]$results.Add([pscustomobject]@{ Prueba = $Test; Resultado = $status; Detalle = $Detail })
}

function Compose {
    docker compose @args | Out-Host
}

# GET al balanceador. Devuelve codigo HTTP, tiempo, cuerpo y JSON (si lo hay).
function Invoke-Http {
    param([string]$Path)
    $raw = curl.exe -s -m 15 -w "`n%{http_code} %{time_total}" "$BaseUrl$Path"
    $text = ($raw -join "`n")
    $idx = $text.LastIndexOf("`n")
    if ($idx -lt 0) {
        $body = ""
        $meta = $text.Trim()
    } else {
        $body = $text.Substring(0, $idx)
        $meta = $text.Substring($idx + 1).Trim()
    }
    $parts = $meta.Split(" ")
    $code = 0
    [void][int]::TryParse($parts[0], [ref]$code)
    $time = 0.0
    if ($parts.Length -gt 1) {
        [void][double]::TryParse($parts[1], [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$time)
    }
    $json = $null
    try { $json = $body | ConvertFrom-Json -ErrorAction Stop } catch { $json = $null }
    return [pscustomobject]@{ Path = $Path; Code = $code; Time = $time; Body = $body; Json = $json }
}

# N consultas seguidas; imprime codigo, tiempo e instancia de cada una.
function Invoke-Probe {
    param([int]$Count = 6, [string]$Path = "/api/health")
    $list = New-Object System.Collections.ArrayList
    foreach ($i in 1..$Count) {
        $r = Invoke-Http $Path
        $inst = "-"
        if ($r.Json -and $r.Json.instance) { $inst = $r.Json.instance }
        Write-Host ("  #{0}  HTTP {1}  {2:N3}s  instance={3}" -f $i, $r.Code, $r.Time, $inst)
        [void]$list.Add($r)
    }
    return ,@($list)
}

function Get-CodeCount {
    param($Probe, [int]$Code)
    return @($Probe | Where-Object { $_.Code -eq $Code }).Count
}

function Get-Instances {
    param($Probe)
    return @($Probe | Where-Object { $_.Json -and $_.Json.instance } | ForEach-Object { $_.Json.instance } | Sort-Object -Unique)
}

function Get-ContainerHealth {
    param([string]$Name)
    $h = docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}" $Name 2>$null
    if ($LASTEXITCODE -ne 0) { return "missing" }
    return ("" + $h).Trim()
}

function Wait-ContainerHealth {
    param([string[]]$Names, [string]$Expected, [int]$TimeoutSec = 90)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $all = $true
        foreach ($n in $Names) {
            if ((Get-ContainerHealth $n) -ne $Expected) { $all = $false }
        }
        if ($all) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Wait-Http200 {
    param([string]$Path = "/api/health", [int]$TimeoutSec = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $r = Invoke-Http $Path
        if ($r.Code -eq 200) { return $true }
        Start-Sleep -Seconds 2
    }
    return $false
}

# ------------------------------------------------------------------- pruebas

Start-Transcript -Path $EvidenceFile -Force | Out-Null
Write-Host "Health Endpoint Monitoring - pruebas empiricas"
Write-Host ("Inicio: {0}   Balanceador: {1}   Evidencia: {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $BaseUrl, $EvidenceFile)

try {
    # ---- Preparacion
    Write-Section "Preparacion"
    if ($Clean) {
        Compose down -v
        Compose up --build -d
    } else {
        Compose up -d
    }
    $ready = Wait-ContainerHealth @("tfu-api-1", "tfu-api-2") "healthy" 120
    Compose ps
    if (-not $ready) { throw "api-1 y/o api-2 no llegaron a estado healthy" }
    if (-not (Wait-Http200 "/api/health" 30)) { throw "el balanceador no responde 200 en /api/health" }

    # ---- Prueba 1
    Write-Section "Prueba 1: ambas replicas sanas"
    $p = Invoke-Probe 6
    $n200 = Get-CodeCount $p 200
    $inst = Get-Instances $p
    Add-Result "1" ($n200 -eq 6) ("{0} de 6 respuestas HTTP 200" -f $n200)
    Add-Result "1" ($inst.Count -eq 2) ("alternancia entre instancias: " + ($inst -join ", "))
    $okHealth = ((Get-ContainerHealth "tfu-api-1") -eq "healthy") -and ((Get-ContainerHealth "tfu-api-2") -eq "healthy")
    Add-Result "1" $okHealth "docker: tfu-api-1 y tfu-api-2 en estado healthy"

    # ---- Prueba 2
    Write-Section "Prueba 2: /health y /health/live sin JWT"
    $live = Invoke-Http "/api/health/live"
    $health = Invoke-Http "/api/health"
    Write-Host ("  GET /api/health/live -> HTTP {0}  {1}" -f $live.Code, $live.Body)
    Write-Host ("  GET /api/health      -> HTTP {0}  {1}" -f $health.Code, $health.Body)
    Add-Result "2" ($live.Code -eq 200) ("GET /api/health/live sin token -> " + $live.Code)
    Add-Result "2" ($health.Code -eq 200) ("GET /api/health sin token -> " + $health.Code)

    # ---- Prueba 3
    Write-Section "Prueba 3: base de datos no disponible en api-1 (FORCE_DB_FAIL)"
    $api1Forced = $true
    $env:API1_FORCE_DB_FAIL = "true"
    Compose up -d api1
    Compose restart loadbalancer
    $unhealthy = Wait-ContainerHealth @("tfu-api-1") "unhealthy" 90
    Start-Sleep -Seconds 2

    Write-Host "  a) consulta directa a api-1 (sin pasar por Nginx)"
    $directRaw = docker compose exec -T api1 node -e "fetch('http://127.0.0.1:3000/api/health').then(async r=>console.log(r.status, await r.text()))"
    $directText = ($directRaw | Out-String).Trim()
    Write-Host ("  " + $directText)
    $directCode = 0
    $directJson = $null
    if ($directText -match '(?s)^(\d{3})\s+(.*)$') {
        $directCode = [int]$Matches[1]
        try { $directJson = $Matches[2] | ConvertFrom-Json -ErrorAction Stop } catch { $directJson = $null }
    }
    Add-Result "3" ($directCode -eq 503) ("api-1 directo -> HTTP " + $directCode + " (esperado 503)")
    Add-Result "3" ($directJson.status -eq "degraded") "api-1 directo -> status degraded"
    Add-Result "3" ($directJson.checks.database.status -eq "down") "api-1 directo -> database: down"

    Write-Host "  b) a traves del balanceador"
    $p = Invoke-Probe 8
    $n200 = Get-CodeCount $p 200
    $inst = Get-Instances $p
    Add-Result "3" ($n200 -eq 8) ("por Nginx: {0} de 8 respuestas HTTP 200" -f $n200)
    Add-Result "3" (($inst.Count -eq 1) -and ($inst[0] -eq "api-2")) ("por Nginx: respondio solo " + ($inst -join ", "))

    Write-Host "  c) estado y logs"
    Compose ps
    Add-Result "3" $unhealthy "docker: tfu-api-1 en estado unhealthy"
    $logs = docker compose logs --tail 20 api1 | Out-String
    Write-Host $logs
    Add-Result "3" ($logs -match "fallo de BD") "log de api-1 registra el fallo de la base"

    # ---- Prueba 4
    Write-Section "Prueba 4: restauracion de api-1"
    Remove-Item Env:API1_FORCE_DB_FAIL -ErrorAction SilentlyContinue
    $api1Forced = $false
    Compose up -d api1
    Compose restart loadbalancer
    $healthy = Wait-ContainerHealth @("tfu-api-1", "tfu-api-2") "healthy" 90
    Start-Sleep -Seconds 3
    Compose ps
    $p = Invoke-Probe 6
    $n200 = Get-CodeCount $p 200
    $inst = Get-Instances $p
    Add-Result "4" $healthy "docker: ambas replicas healthy"
    Add-Result "4" ($n200 -eq 6) ("{0} de 6 respuestas HTTP 200" -f $n200)
    Add-Result "4" ($inst.Count -eq 2) ("alternancia restablecida: " + ($inst -join ", "))

    # ---- Prueba 5
    Write-Section "Prueba 5: api-1 detenida"
    Compose stop api1
    $p = Invoke-Probe 6
    $n200 = Get-CodeCount $p 200
    $inst = Get-Instances $p
    $first = $p[0].Time
    $restTimes = @($p | Select-Object -Skip 1 | ForEach-Object { $_.Time })
    $restMax = ($restTimes | Measure-Object -Maximum).Maximum
    Add-Result "5" ($n200 -eq 6) ("{0} de 6 respuestas HTTP 200" -f $n200)
    Add-Result "5" (($inst.Count -eq 1) -and ($inst[0] -eq "api-2")) ("respondio solo " + ($inst -join ", "))
    Add-Result "5" ($first -lt 6) ("primera respuesta {0:N2}s (incluye proxy_connect_timeout de 2s); las demas hasta {1:N3}s" -f $first, $restMax)
    Compose start api1
    [void](Wait-ContainerHealth @("tfu-api-1") "healthy" 90)
    Compose ps

    # ---- Prueba 6
    Write-Section "Prueba 6: ambas replicas detenidas"
    Compose stop api1 api2
    $r = Invoke-Http "/api/health"
    Write-Host ("  GET /api/health -> HTTP {0} en {1:N2}s  {2}" -f $r.Code, $r.Time, $r.Body)
    Add-Result "6" ($r.Code -eq 503) ("codigo observado: {0} (esperado 503; si es 504 falta '=503' en error_page de nginx.conf)" -f $r.Code)
    Add-Result "6" ($r.Json -and ($r.Json.status -eq "unavailable")) "cuerpo JSON de error controlado (status unavailable)"
    Compose start api1 api2
    $back = Wait-ContainerHealth @("tfu-api-1", "tfu-api-2") "healthy" 90
    Compose ps
    Add-Result "6" $back "docker: ambas replicas vuelven a healthy"
    Add-Result "6" (Wait-Http200 "/api/health" 60) "el servicio se recupera: /api/health vuelve a responder 200"
}
catch {
    $aborted = $true
    Write-Host ("ABORTADO: " + $_) -ForegroundColor Red
}
finally {
    Remove-Item Env:API1_FORCE_DB_FAIL -ErrorAction SilentlyContinue
    if ($api1Forced) {
        Write-Host "Restaurando api-1 a su configuracion normal..."
        Compose up -d api1
        Compose restart loadbalancer
    }
    Write-Section "Resumen"
    if ($results.Count -gt 0) {
        $results | Format-Table -AutoSize -Wrap | Out-String | Write-Host
    }
    $failures = @($results | Where-Object { $_.Resultado -eq "FAIL" }).Count
    $total = $results.Count
    Write-Host ("Verificaciones: {0}   Falladas: {1}" -f $total, $failures)
    Write-Host ("Evidencia guardada en: " + $EvidenceFile)
    Stop-Transcript | Out-Null
}

if ($aborted -or ($failures -gt 0)) { exit 1 }
exit 0