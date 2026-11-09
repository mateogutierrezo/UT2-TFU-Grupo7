<#
Prueba los microservicios integrados en Docker: flujo normal, caída de Proyectos,
aislamiento, Circuit Breaker abierto/rechazo rápido y recuperación.

Uso desde la raíz del repositorio:
  powershell -ExecutionPolicy Bypass -File .\scripts\prueba-disponibilidad.ps1

Requiere que docker compose up esté activo y solicita un JWT de prueba.
Guarda mediciones CSV en evidencia/ y siempre intenta dejar Proyectos iniciado.
#>
param(
  [string]$BaseUrl = "http://localhost:8080",
  [int]$ResetTimeoutMs = 10000,
  [int]$FastRejectMaxMs = 1000
)

$ErrorActionPreference = "Stop"
$repositoryRoot = Split-Path -Parent $PSScriptRoot
$evidenceDirectory = Join-Path $repositoryRoot "evidencia"
$evidencePath = Join-Path $evidenceDirectory ("disponibilidad-{0}.csv" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$logEvidencePath = Join-Path $evidenceDirectory ("disponibilidad-{0}-circuitos.txt" -f (Get-Date -Format "yyyyMMdd-HHmmss"))
$testStartedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$script:evidenceStarted = $false
$script:projectsStoppedByTest = $false
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Net.Http")
$script:httpClient = [System.Net.Http.HttpClient]::new()

function Write-Evidence {
  param(
    [string]$Scenario,
    [string]$Request,
    [string]$Status,
    [double]$DurationMs = 0,
    [string]$CircuitState = "",
    [string]$Note = ""
  )

  $row = [pscustomobject]@{
    timestamp     = (Get-Date).ToString("o")
    scenario      = $Scenario
    request       = $Request
    status        = $Status
    duration_ms   = [math]::Round($DurationMs, 2)
    circuit_state = $CircuitState
    note          = $Note
  }

  if ($script:evidenceStarted) {
    $row | Export-Csv -LiteralPath $evidencePath -NoTypeInformation -Append -Encoding UTF8
  }
  else {
    $row | Export-Csv -LiteralPath $evidencePath -NoTypeInformation -Encoding UTF8
    $script:evidenceStarted = $true
  }
}

function Invoke-Api {
  param(
    [ValidateSet("GET", "POST")]
    [string]$Method,
    [string]$Path,
    [string]$Token = "",
    [object]$Body = $null
  )

  $uri = "{0}{1}" -f $BaseUrl.TrimEnd("/"), $Path
  $request = [System.Net.Http.HttpRequestMessage]::new(
    [System.Net.Http.HttpMethod]::new($Method),
    $uri
  )

  if ($Token) {
    $request.Headers.Authorization =
      [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $Token)
  }

  if ($null -ne $Body) {
    $json = ConvertTo-Json -InputObject $Body -Depth 10 -Compress
    $request.Content = [System.Net.Http.StringContent]::new(
      $json,
      [System.Text.Encoding]::UTF8,
      "application/json"
    )
  }

  $timer = [System.Diagnostics.Stopwatch]::StartNew()
  try {
    $response = $script:httpClient.SendAsync($request).GetAwaiter().GetResult()
    $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
    $timer.Stop()

    return [pscustomobject]@{
      StatusCode = [int]$response.StatusCode
      DurationMs = $timer.Elapsed.TotalMilliseconds
      Body       = $content
    }
  }
  finally {
    $request.Dispose()
    if ($null -ne $response) {
      $response.Dispose()
    }
  }
}

function Invoke-ApiBatch {
  param(
    [string]$Path,
    [string]$Token,
    [int]$Count
  )

  $pending = New-Object System.Collections.Generic.List[object]
  $results = New-Object System.Collections.Generic.List[object]

  try {
    for ($i = 1; $i -le $Count; $i++) {
      $request = [System.Net.Http.HttpRequestMessage]::new(
        [System.Net.Http.HttpMethod]::Get,
        ("{0}{1}" -f $BaseUrl.TrimEnd("/"), $Path)
      )
      $request.Headers.Authorization =
        [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $Token)
      $timer = [System.Diagnostics.Stopwatch]::StartNew()
      $sendTask = $script:httpClient.SendAsync($request)
      $pending.Add([pscustomobject]@{
        Index     = $i
        Request   = $request
        Timer     = $timer
        SendTask  = $sendTask
      })
    }

    foreach ($item in $pending) {
      $response = $item.SendTask.GetAwaiter().GetResult()
      try {
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $item.Timer.Stop()
        $results.Add([pscustomobject]@{
          Index      = $item.Index
          StatusCode = [int]$response.StatusCode
          DurationMs = $item.Timer.Elapsed.TotalMilliseconds
          Body       = $content
        })
      }
      finally {
        $response.Dispose()
      }
    }

    return @($results | Sort-Object Index)
  }
  finally {
    foreach ($item in $pending) {
      $item.Request.Dispose()
    }
  }
}

function Invoke-Compose {
  param([string[]]$Arguments)

  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = "Continue"
  try {
    $output = & docker compose --progress quiet @Arguments 2>&1
    $exitCode = $LASTEXITCODE
  }
  finally {
    $ErrorActionPreference = $previousErrorActionPreference
  }

  $output = @($output | ForEach-Object { "$_" })
  if ($exitCode -ne 0) {
    throw "docker compose $($Arguments -join ' ') fallo (codigo $exitCode): $($output -join ' ')"
  }
  return ($output -join [Environment]::NewLine)
}

function Get-ServiceHealth {
  param([string]$Service)

  $nodeScript = "fetch('http://127.0.0.1:3000/api/health').then(async r=>{console.log(await r.text());process.exitCode=r.ok?0:1}).catch(e=>{console.error(e);process.exitCode=1})"
  $output = Invoke-Compose -Arguments @(
    "exec", "-T", $Service, "node", "-e", $nodeScript
  )

  try {
    return ($output | ConvertFrom-Json)
  }
  catch {
    throw "No se pudo interpretar el healthcheck de $Service`: $output"
  }
}

function Assert-Status {
  param(
    [object]$Response,
    [int]$Expected,
    [string]$Description
  )

  if ($Response.StatusCode -ne $Expected) {
    throw "$Description`: se esperaba HTTP $Expected y se recibio HTTP $($Response.StatusCode). Respuesta: $($Response.Body)"
  }
}

function Wait-ProjectsHealthy {
  $deadline = (Get-Date).AddSeconds(90)
  do {
    try {
      $containerId = (Invoke-Compose -Arguments @("ps", "-q", "projects-service")).Trim()
      if ($containerId) {
        $healthOutput = & docker inspect --format "{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}" $containerId 2>$null
        $inspectExitCode = $LASTEXITCODE
        $health = (@($healthOutput) -join "").Trim()
        if ($inspectExitCode -eq 0 -and $health -eq "healthy") {
          return
        }
      }
    }
    catch {
      Write-Verbose "Esperando que projects-service quede healthy: $_"
    }
    Start-Sleep -Seconds 2
  } while ((Get-Date) -lt $deadline)

  throw "projects-service no llego a healthy dentro de 90 segundos"
}

try {
  Set-Location $repositoryRoot
  New-Item -ItemType Directory -Force $evidenceDirectory | Out-Null

  foreach ($service in @("identity-service", "projects-service", "tasks-service")) {
    $health = Get-ServiceHealth -Service $service
    if ($health.status -ne "ok") {
      throw "$service no está saludable: $($health | ConvertTo-Json -Compress)"
    }
    Write-Evidence -Scenario "Precondicion" -Request "$service /api/health" `
      -Status "HTTP 200" -CircuitState $health.checks.dependencies.projectsCircuit.state `
      -Note "status=$($health.status); DB=$($health.checks.database.status)"
    Write-Host "$service saludable; base de datos $($health.checks.database.status)"
  }

  $gatewayHealth = Invoke-Api -Method GET -Path "/api/health"
  Assert-Status $gatewayHealth 200 "Health del gateway"
  Write-Evidence -Scenario "Precondicion" -Request "GET /api/health (gateway)" `
    -Status "HTTP $($gatewayHealth.StatusCode)" -DurationMs $gatewayHealth.DurationMs `
    -Note $gatewayHealth.Body

  $randomBytes = New-Object byte[] 16
  $randomGenerator = [System.Security.Cryptography.RandomNumberGenerator]::Create()
  try {
    $randomGenerator.GetBytes($randomBytes)
  }
  finally {
    $randomGenerator.Dispose()
  }
  $testEmail = "availability-{0}@example.test" -f [Guid]::NewGuid().ToString("N")
  $testPassword = "Test-{0}-a1" -f ([System.BitConverter]::ToString($randomBytes).Replace("-", "").ToLowerInvariant())

  Write-Host "`nCreando cuenta temporal de prueba e iniciando sesion..."
  $registerResponse = Invoke-Api -Method POST -Path "/api/auth/register" `
    -Body @{ email = $testEmail; password = $testPassword }
  Assert-Status $registerResponse 201 "Registrar usuario temporal"
  Write-Evidence -Scenario "Preparacion" -Request "POST /api/auth/register" `
    -Status "HTTP $($registerResponse.StatusCode)" -DurationMs $registerResponse.DurationMs `
    -Note "Cuenta temporal unica; la contrasena no se guarda en evidencia."

  $loginResponse = Invoke-Api -Method POST -Path "/api/auth/login" `
    -Body @{ email = $testEmail; password = $testPassword }
  Assert-Status $loginResponse 200 "Login del usuario temporal"
  $token = ($loginResponse.Body | ConvertFrom-Json).token
  if ([string]::IsNullOrWhiteSpace($token)) {
    throw "El login fue exitoso pero no devolvio un JWT."
  }
  Write-Evidence -Scenario "Preparacion" -Request "POST /api/auth/login" `
    -Status "HTTP $($loginResponse.StatusCode)" -DurationMs $loginResponse.DurationMs `
    -Note "JWT usado solo en memoria; no se guarda en evidencia."

  Write-Host "`nEscenario normal: creando proyecto y tarea de prueba..."
  $projectResponse = Invoke-Api -Method POST -Path "/api/projects" -Token $token `
    -Body @{ name = "Prueba disponibilidad $(Get-Date -Format 'yyyyMMdd-HHmmss')" }
  Assert-Status $projectResponse 201 "Crear proyecto"
  $projectResult = $projectResponse.Body | ConvertFrom-Json
  $projectId = $projectResult.project.id
  Write-Evidence -Scenario "Funcionamiento normal" -Request "POST /api/projects" `
    -Status "HTTP $($projectResponse.StatusCode)" -DurationMs $projectResponse.DurationMs `
    -Note "project_id=$projectId"

  $taskResponse = Invoke-Api -Method POST -Path "/api/tasks" -Token $token `
    -Body @{ title = "Tarea disponibilidad"; project_id = $projectId }
  Assert-Status $taskResponse 201 "Crear tarea (incluye consulta SOAP)"
  Write-Evidence -Scenario "Funcionamiento normal" -Request "POST /api/tasks" `
    -Status "HTTP $($taskResponse.StatusCode)" -DurationMs $taskResponse.DurationMs `
    -Note "La creacion valida membresia mediante SOAP"

  $listResponse = Invoke-Api -Method GET -Path "/api/tasks" -Token $token
  Assert-Status $listResponse 200 "Listar tareas (incluye consulta SOAP)"
  Write-Evidence -Scenario "Funcionamiento normal" -Request "GET /api/tasks" `
    -Status "HTTP $($listResponse.StatusCode)" -DurationMs $listResponse.DurationMs

  Write-Host "Esperando 11 segundos para vaciar la ventana movil previa del Circuit Breaker..."
  Start-Sleep -Seconds 11

  $beforeFailure = Get-ServiceHealth -Service "tasks-service"
  if ($beforeFailure.checks.dependencies.projectsCircuit.state -ne "CLOSED") {
    throw "El circuito no esta CLOSED antes de inyectar la falla"
  }

  Write-Host "`nDeteniendo solo projects-service..."
  $script:projectsStoppedByTest = $true
  Invoke-Compose -Arguments @("stop", "projects-service") | Out-Null
  Start-Sleep -Seconds 2

  foreach ($service in @("identity-service", "tasks-service")) {
    $health = Get-ServiceHealth -Service $service
    if ($health.status -ne "ok") {
      throw "$service dejo de estar saludable con Proyectos detenido"
    }
    Write-Evidence -Scenario "Aislamiento de fallos" -Request "$service /api/health" `
      -Status "HTTP 200" -CircuitState $health.checks.dependencies.projectsCircuit.state `
      -Note "Servicio y base propios continuan disponibles"
  }

  Write-Host "`nEnviando cinco solicitudes concurrentes a Tareas dentro de la ventana movil del Circuit Breaker..."
  $failureResponses = Invoke-ApiBatch -Path "/api/tasks" -Token $token -Count 5
  foreach ($failureResponse in $failureResponses) {
    Write-Host ("Fallo {0}: HTTP {1}, {2:N0} ms" -f $failureResponse.Index, $failureResponse.StatusCode, $failureResponse.DurationMs)
    Write-Evidence -Scenario "Proyectos detenido" -Request "GET /api/tasks #$($failureResponse.Index)" `
      -Status "HTTP $($failureResponse.StatusCode)" -DurationMs $failureResponse.DurationMs
    Assert-Status $failureResponse 503 "Solicitud fallida #$($failureResponse.Index)"
  }

  $openHealth = Get-ServiceHealth -Service "tasks-service"
  $circuit = $openHealth.checks.dependencies.projectsCircuit
  Write-Evidence -Scenario "Circuit Breaker" -Request "Estado tras cinco fallos" `
    -Status $openHealth.status -CircuitState $circuit.state `
    -Note "failures=$($circuit.failures); stateChanges=$($circuit.stateChanges)"
  if ($circuit.state -ne "OPEN") {
    throw "Se espero Circuit Breaker OPEN tras cinco fallos; estado actual: $($circuit.state)."
  }

  $rejectResponse = Invoke-Api -Method GET -Path "/api/tasks" -Token $token
  Write-Host ("Rechazo con circuito abierto: HTTP {0}, {1:N0} ms" -f $rejectResponse.StatusCode, $rejectResponse.DurationMs)
  Write-Evidence -Scenario "Circuit Breaker abierto" -Request "GET /api/tasks (rechazo)" `
    -Status "HTTP $($rejectResponse.StatusCode)" -DurationMs $rejectResponse.DurationMs `
    -CircuitState $circuit.state
  Assert-Status $rejectResponse 503 "Rechazo del circuito abierto"
  if ($rejectResponse.DurationMs -ge $FastRejectMaxMs) {
    throw "El rechazo tomo $([math]::Round($rejectResponse.DurationMs, 2)) ms; se esperaba menos de $FastRejectMaxMs ms"
  }

  $rejectHealth = Get-ServiceHealth -Service "tasks-service"
  $rejectStats = $rejectHealth.checks.dependencies.projectsCircuit
  Write-Evidence -Scenario "Circuit Breaker abierto" -Request "Contadores tras rechazo" `
    -Status $rejectHealth.status -CircuitState $rejectStats.state `
    -Note "rejects=$($rejectStats.rejects); failures=$($rejectStats.failures)"
  if ($rejectStats.rejects -lt 1) {
    throw "El contador rejects no aumento tras la solicitud con circuito abierto"
  }

  Write-Host "`nRestaurando projects-service..."
  Invoke-Compose -Arguments @("start", "projects-service") | Out-Null
  Wait-ProjectsHealthy
  $script:projectsStoppedByTest = $false

  Write-Host "Esperando el reset del Circuit Breaker ($ResetTimeoutMs ms)..."
  Start-Sleep -Milliseconds ($ResetTimeoutMs + 1000)

  $recoveryResponse = Invoke-Api -Method GET -Path "/api/tasks" -Token $token
  Assert-Status $recoveryResponse 200 "Consulta a Tareas tras recuperar Proyectos"
  Write-Evidence -Scenario "Recuperacion" -Request "GET /api/tasks" `
    -Status "HTTP $($recoveryResponse.StatusCode)" -DurationMs $recoveryResponse.DurationMs `
    -Note "Proyectos volvio a healthy"

  $recoveredHealth = Get-ServiceHealth -Service "tasks-service"
  $recoveredCircuit = $recoveredHealth.checks.dependencies.projectsCircuit
  Write-Evidence -Scenario "Recuperacion" -Request "Estado final del Circuit Breaker" `
    -Status $recoveredHealth.status -CircuitState $recoveredCircuit.state `
    -Note "successes=$($recoveredCircuit.successes); rejects=$($recoveredCircuit.rejects); stateChanges=$($recoveredCircuit.stateChanges)"
  if ($recoveredCircuit.state -ne "CLOSED") {
    throw "Se esperaba Circuit Breaker CLOSED tras una llamada de prueba exitosa; estado: $($recoveredCircuit.state)."
  }

  Write-Host "`nPRUEBA COMPLETADA: todos los escenarios pasaron"
  Write-Host "Evidencia CSV: $evidencePath"
}
catch {
  Write-Error $_
  Write-Host "La evidencia parcial, si se genero, esta en: $evidencePath"
  throw
}
finally {
  if ($script:projectsStoppedByTest) {
    Write-Host "Asegurando que projects-service quede iniciado..."
    & docker compose start projects-service | Out-Null
  }
  $circuitLogs = & docker compose logs --since $testStartedAt tasks-service 2>&1 |
    Select-String "\[circuit:projects\]"
  if ($LASTEXITCODE -eq 0 -and $circuitLogs) {
    $circuitLogs | ForEach-Object { $_.Line } |
      Set-Content -LiteralPath $logEvidencePath -Encoding UTF8
    Write-Host "Transiciones del Circuit Breaker: $logEvidencePath"
  }
  $script:httpClient.Dispose()
}
