param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

# VANTEGRATE - Salesforce Project Generator with CI/CD Pipeline
# Version: 2.1.0

# --- CONFIGURACION ---
$Collaborators = @()
$EnforceAdmins = $true
$WaitForWorkflowTimeout = 300
# ---------------------

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Gray
}

function Wait-ForWorkflowCompletion {
    param(
        [int]$TimeoutSeconds = 300
    )
    
    Write-Info "Esperando que el workflow inicial complete..."
    
    $startTime = Get-Date
    
    while ($true) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        
        if ($elapsed -gt $TimeoutSeconds) {
            Write-Warning "Timeout alcanzado despues de $TimeoutSeconds segundos."
            return $false
        }
        
        # Ejecutar desde el directorio del repo, sin necesidad de --repo flag
        $runsJson = gh run list --limit 1 --json status,conclusion 2>$null
        
        if ($runsJson) {
            $runs = $runsJson | ConvertFrom-Json
            
            if ($runs.Count -gt 0) {
                $latestRun = $runs[0]
                $status = $latestRun.status
                $conclusion = $latestRun.conclusion
                
                Write-Host "." -NoNewline -ForegroundColor Gray
                
                if ($status -eq "completed") {
                    Write-Host ""
                    if ($conclusion -eq "success") {
                        Write-Success "Workflow completado exitosamente."
                        return $true
                    }
                    else {
                        Write-Warning "Workflow completo con estado: $conclusion"
                        return $true
                    }
                }
            }
            else {
                Write-Host "x" -NoNewline -ForegroundColor Yellow
            }
        }
        else {
            Write-Host "?" -NoNewline -ForegroundColor Yellow
        }
        
        Start-Sleep -Seconds 10
    }
    
    return $false
}

# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "     VANTEGRATE - Salesforce Project Generator              " -ForegroundColor Magenta
Write-Host "============================================================" -ForegroundColor Magenta
Write-Host "  Proyecto: $ProjectName" -ForegroundColor White

# =============================================================================
# PASO 1: Crear estructura Salesforce
# =============================================================================
Write-Step "Generando estructura Salesforce..."

sf project generate --name $ProjectName --template standard | Out-Null
Set-Location $ProjectName

Write-Success "Proyecto Salesforce generado."

# =============================================================================
# PASO 2: Copiar README corporativo
# =============================================================================
Write-Step "Configurando README.md..."

if (Test-Path "..\templates\README.md") {
    Copy-Item -Path "..\templates\README.md" -Destination "README.md" -Force
    Write-Success "README.md corporativo aplicado."
}
else {
    Write-Warning "Template README.md no encontrado."
}

# =============================================================================
# PASO 3: Crear .gitignore robusto
# =============================================================================
Write-Step "Creando .gitignore..."

$gitignoreContent = @'

# Salesforce
.sfdx/
.sf/
.localdevserver/

# IDE
.vscode/
.idea/
*.sublime-*

# Dependencies
node_modules/

# Build & Coverage
coverage/
dist/
.nyc_output/

# Auth files
auth*.txt
*auth*.json

# OS
.DS_Store
Thumbs.db

# Logs
*.log
npm-debug.log*
'@

Add-Content -Path '.gitignore' -Value $gitignoreContent
Write-Success ".gitignore configurado."

# =============================================================================
# PASO 4: Copiar pipeline CI/CD
# =============================================================================
Write-Step "Configurando pipeline CI/CD..."

$workflowPath = '.github\workflows'
New-Item -Path $workflowPath -ItemType Directory -Force | Out-Null

if (Test-Path '..\templates\pipeline.yml') {
    Copy-Item -Path '..\templates\pipeline.yml' -Destination "$workflowPath\pipeline.yml" -Force
    Write-Success "Pipeline CI/CD configurado."
}
else {
    Write-Warning "Template pipeline.yml no encontrado!"
}

# =============================================================================
# PASO 5: Inicializar Git y hacer commit inicial
# =============================================================================
Write-Step "Inicializando repositorio Git..."

git init --quiet
git add .
git commit -m "Initial commit: Salesforce project with CI/CD pipeline" --quiet

Write-Success "Repositorio Git inicializado."

# =============================================================================
# PASO 6: Crear repositorio en GitHub y hacer push
# =============================================================================
Write-Step "Creando repositorio en GitHub..."

gh repo create $ProjectName --public --source=. --remote=origin --push | Out-Null

Write-Success "Repositorio creado en GitHub."

# =============================================================================
# PASO 7: Crear rama develop
# =============================================================================
Write-Step "Configurando ramas..."

git checkout -b develop --quiet
git push -u origin develop --quiet 2>$null
git checkout main --quiet

Write-Success "Rama develop creada y publicada."

# =============================================================================
# PASO 8: Invitar colaboradores
# =============================================================================
if ($Collaborators.Count -gt 0) {
    Write-Step "Invitando colaboradores..."
    
    foreach ($user in $Collaborators) {
        gh api repos/:owner/$ProjectName/collaborators/$user --method PUT -f permission=push 2>$null
        Write-Success "Invitacion enviada a: $user"
    }
}

# =============================================================================
# PASO 9: Esperar que el primer workflow complete
# =============================================================================
Write-Step "Esperando ejecucion inicial del workflow..."
Write-Info "Esto es necesario para que GitHub reconozca los status checks."

Start-Sleep -Seconds 10

$workflowSuccess = Wait-ForWorkflowCompletion -TimeoutSeconds $WaitForWorkflowTimeout

if (-not $workflowSuccess) {
    Write-Warning "No se pudo confirmar la ejecucion del workflow."
    Write-Info "Continua con la configuracion de todas formas..."
}

# =============================================================================
# PASO 10: Aplicar proteccion de ramas
# =============================================================================
Write-Step "Aplicando proteccion de ramas..."

$protectionPayload = @{
    required_status_checks = @{
        strict   = $true
        contexts = @('Quality Check', 'Validate PR')
    }
    enforce_admins                 = $EnforceAdmins
    required_pull_request_reviews  = @{
        dismiss_stale_reviews          = $true
        required_approving_review_count = 1
    }
    restrictions                   = $null
    allow_force_pushes             = $false
    allow_deletions                = $false
} | ConvertTo-Json -Depth 10

$protectionPayload | gh api "repos/:owner/$ProjectName/branches/main/protection" --method PUT --input - 2>$null | Out-Null
Write-Success "Proteccion aplicada a main."

$protectionPayload | gh api "repos/:owner/$ProjectName/branches/develop/protection" --method PUT --input - 2>$null | Out-Null
Write-Success "Proteccion aplicada a develop."

# =============================================================================
# RESUMEN FINAL
# =============================================================================
Write-Host ""
Write-Host "============================================================" -ForegroundColor Green
Write-Host "     PROYECTO CONFIGURADO EXITOSAMENTE                      " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  PROXIMOS PASOS:" -ForegroundColor Yellow
Write-Host "  1. Configurar secreto SFDX_AUTH_URL_DEV en GitHub" -ForegroundColor Gray
Write-Host "  2. Configurar secreto SFDX_AUTH_URL_PROD en GitHub" -ForegroundColor Gray
Write-Host "  3. Crear environment production con reviewers" -ForegroundColor Gray
Write-Host ""
Write-Host "  Para obtener el SFDX Auth URL ejecuta:" -ForegroundColor Cyan
Write-Host "  sf org display --verbose --target-org TU_ORG" -ForegroundColor Gray
Write-Host ""
