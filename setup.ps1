param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName
)

# --- CONFIGURACIÓN ---
$Collaborators = @()
$EnforceAdmins = $true
# ---------------------

Write-Host 'Iniciando automatización para el proyecto:' $ProjectName -ForegroundColor Cyan

# 1. Crear estructura Salesforce
Write-Host 'Generando estructura Salesforce...' -ForegroundColor Yellow
cmd /c sf project generate --name $ProjectName --template standard
Set-Location $ProjectName

# Reemplazar README por template corporativo
Write-Host 'Generando README.md profesional...' -ForegroundColor Yellow

# CORRECCIÓN: Todo en una línea para evitar errores de espacios ocultos
Copy-Item -Path "..\templates\README.md" -Destination "README.md" -Force

# 1.1 Crear .gitignore robusto
Write-Host 'Creando .gitignore...' -ForegroundColor Yellow
$gitignoreContent = @'
.sfdx
.sf
.vscode
.idea
coverage
dist
node_modules
**/*.wwoff2
**/*.js-map
auth_*.txt
'@
Add-Content -Path '.gitignore' -Value $gitignoreContent

# 1.5 Copiar pipeline CI/CD desde template
Write-Host 'Copiando pipeline CI/CD...' -ForegroundColor Yellow
$workflowPath = '.github\workflows'
New-Item -Path $workflowPath -ItemType Directory -Force | Out-Null

Copy-Item -Path '..\templates\pipeline.yml' `
          -Destination "$workflowPath\pipeline.yml" `
          -Force

# 2. Inicializar Git
Write-Host 'Inicializando Git...' -ForegroundColor Yellow
git init
git add .
git commit -m 'Initial commit: Salesforce project with CI/CD'

# 3. Crear repositorio en GitHub
Write-Host 'Creando repositorio en GitHub...' -ForegroundColor Yellow
gh repo create $ProjectName --public --source=. --remote=origin --push

# 4. Ramas
Write-Host 'Configurando ramas...' -ForegroundColor Yellow
git checkout -b develop
git push -u origin develop
git checkout main

# 5. Colaboradores
Write-Host 'Invitando colaboradores...' -ForegroundColor Yellow
foreach ($user in $Collaborators) {
    gh repo collaborator add $user 
}

# 6. Protección de ramas
Write-Host 'Aplicando protección de ramas...' -ForegroundColor Yellow

$payload = @{
    required_status_checks = @{
        strict = $true
        contexts = @('quality-check', 'validate-pr')
    }
    enforce_admins = $EnforceAdmins
    required_pull_request_reviews = @{
        dismiss_stale_reviews = $true
        required_approving_review_count = 1
    }
    restrictions = $null
} | ConvertTo-Json -Depth 10

$mainBranchUrl    = 'repos/:owner/' + $ProjectName + '/branches/main/protection'
$developBranchUrl = 'repos/:owner/' + $ProjectName + '/branches/develop/protection'

$payload | gh api $mainBranchUrl --method PUT --input - | Out-Null
$payload | gh api $developBranchUrl --method PUT --input - | Out-Null

Write-Host 'Proyecto listo correctamente.' -ForegroundColor Green
Write-Host 'Recuerda configurar los secretos SFDX_AUTH_URL_DEV y SFDX_AUTH_URL_PROD en GitHub.'
