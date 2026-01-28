param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectName,
    
    [Parameter(Mandatory = $false)]
    [string]$Organization = '',
    
    [Parameter(Mandatory = $false)]
    [string[]]$Collaborators = @(),
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('public', 'private')]
    [string]$Visibility = 'public',
    
    [Parameter(Mandatory = $false)]
    [switch]$EnforceAdmins,
    
    [Parameter(Mandatory = $false)]
    [int]$RequiredApprovals = 1,
    
    [Parameter(Mandatory = $false)]
    [int]$WaitForWorkflowTimeout = 300,
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeSlackIntegration,
    
    [Parameter(Mandatory = $false)]
    [switch]$SkipBranchProtection
)

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  VANTEGRATE - Salesforce Project Generator with CI/CD Pipeline           ║
# ║  Version: 3.0.0                                                          ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

$ErrorActionPreference = 'Stop'
$script:HasErrors = $false
$script:StartTime = Get-Date
$script:ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE LOGGING
# ═══════════════════════════════════════════════════════════════════════════════

function Write-Banner {
    $width = 60
    $line = [string]::new([char]0x2550, $width)
    
    Write-Host
    Write-Host ([char]0x2554 + $line + [char]0x2557) -ForegroundColor Magenta
    Write-Host ([char]0x2551 + '  VANTEGRATE - Salesforce Project Generator'.PadRight($width) + [char]0x2551) -ForegroundColor Magenta
    Write-Host ([char]0x2551 + '  Version 3.0.0'.PadRight($width) + [char]0x2551) -ForegroundColor Magenta
    Write-Host ([char]0x255A + $line + [char]0x255D) -ForegroundColor Magenta
    Write-Host
}

function Write-Config {
    $border = [string]::new([char]0x2500, 58)
    
    Write-Host ([char]0x250C + $border + [char]0x2510) -ForegroundColor DarkGray
    Write-Host ([char]0x2502 + '  CONFIGURACION'.PadRight(58) + [char]0x2502) -ForegroundColor DarkGray
    Write-Host ([char]0x251C + $border + [char]0x2524) -ForegroundColor DarkGray
    
    $configItems = @(
        @('Proyecto', $ProjectName),
        @('Organizacion', $(if ($Organization) { $Organization } else { 'Personal' })),
        @('Visibilidad', $Visibility),
        @('Rama principal', 'master'),
        @('Colaboradores', $(if ($Collaborators.Count -gt 0) { $Collaborators -join ', ' } else { 'Ninguno' })),
        @('Slack', $(if ($IncludeSlackIntegration) { 'Habilitado' } else { 'Deshabilitado' })),
        @('Aprobaciones requeridas', $RequiredApprovals.ToString())
    )
    
    foreach ($item in $configItems) {
        $label = ('  ' + $item[0] + ':').PadRight(25)
        $value = $item[1].ToString().PadRight(33)
        Write-Host ([char]0x2502) -NoNewline -ForegroundColor DarkGray
        Write-Host $label -NoNewline -ForegroundColor Gray
        Write-Host $value -NoNewline -ForegroundColor White
        Write-Host ([char]0x2502) -ForegroundColor DarkGray
    }
    
    Write-Host ([char]0x2514 + $border + [char]0x2518) -ForegroundColor DarkGray
    Write-Host
}

function Write-Step {
    param([string]$Message, [int]$StepNumber)
    $timestamp = (Get-Date).ToString('HH:mm:ss')
    Write-Host
    Write-Host ([char]0x25B6) -NoNewline -ForegroundColor Cyan
    Write-Host " PASO $StepNumber " -NoNewline -ForegroundColor Cyan
    Write-Host ([char]0x2502) -NoNewline -ForegroundColor DarkGray
    Write-Host " $Message " -NoNewline -ForegroundColor White
    Write-Host "[$timestamp]" -ForegroundColor DarkGray
}

function Write-Success {
    param([string]$Message)
    Write-Host '    ' -NoNewline
    Write-Host ([char]0x2714) -NoNewline -ForegroundColor Green
    Write-Host " $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host '    ' -NoNewline
    Write-Host ([char]0x26A0) -NoNewline -ForegroundColor Yellow
    Write-Host " $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host '    ' -NoNewline
    Write-Host ([char]0x2718) -NoNewline -ForegroundColor Red
    Write-Host " $Message" -ForegroundColor Red
    $script:HasErrors = $true
}

function Write-Info {
    param([string]$Message)
    Write-Host '    ' -NoNewline
    Write-Host ([char]0x2022) -NoNewline -ForegroundColor DarkGray
    Write-Host " $Message" -ForegroundColor Gray
}

function Write-Divider {
    Write-Host
    Write-Host ([string]::new([char]0x2500, 60)) -ForegroundColor DarkGray
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE VALIDACION
# ═══════════════════════════════════════════════════════════════════════════════

function Test-Command {
    param([string]$Command)
    $null = Get-Command $Command -ErrorAction SilentlyContinue
    return $?
}

function Test-Prerequisites {
    Write-Step -Message 'Verificando prerequisitos' -StepNumber 0
    
    $allGood = $true
    
    # Verificar Git
    if (Test-Command 'git') {
        $gitVersion = git --version 2>$null
        Write-Success "Git instalado: $gitVersion"
    }
    else {
        Write-Error 'Git no esta instalado'
        Write-Info 'Descargar desde: https://git-scm.com/'
        $allGood = $false
    }
    
    # Verificar GitHub CLI
    if (Test-Command 'gh') {
        $ghVersion = (gh --version 2>$null | Select-Object -First 1)
        Write-Success "GitHub CLI instalado: $ghVersion"
        
        # Verificar autenticacion
        $authCheck = gh auth status 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Success 'GitHub CLI autenticado correctamente'
        }
        else {
            Write-Error 'GitHub CLI no autenticado'
            Write-Info 'Ejecutar: gh auth login'
            $allGood = $false
        }
    }
    else {
        Write-Error 'GitHub CLI no esta instalado'
        Write-Info 'Descargar desde: https://cli.github.com/'
        $allGood = $false
    }
    
    # Verificar Salesforce CLI
    if (Test-Command 'sf') {
        try {
            $sfVersionOutput = sf --version 2>&1
            $sfVersion = ($sfVersionOutput | Where-Object { $_ -match '@salesforce/cli' } | Select-Object -First 1)
            if (-not $sfVersion) {
                $sfVersion = ($sfVersionOutput | Select-Object -First 1)
            }
            Write-Success "Salesforce CLI instalado: $sfVersion"
        }
        catch {
            Write-Success 'Salesforce CLI instalado'
        }
    }
    else {
        Write-Error 'Salesforce CLI no esta instalado'
        Write-Info 'Ejecutar: npm install -g @salesforce/cli'
        $allGood = $false
    }
    
    # Verificar que el directorio no exista
    if (Test-Path $ProjectName) {
        Write-Error "El directorio $ProjectName ya existe localmente"
        Write-Info 'Eliminar el directorio o usar otro nombre'
        $allGood = $false
    }
    

    
    # Verificar templates
    $templatesPath = Join-Path -Path $script:ScriptDir -ChildPath 'templates'
    if (Test-Path $templatesPath) {
        Write-Success 'Directorio templates encontrado'
    }
    else {
        Write-Warning 'Directorio templates no encontrado - se usaran valores por defecto'
    }
    
    return $allGood
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE WORKFLOW
# ═══════════════════════════════════════════════════════════════════════════════

function Wait-ForWorkflowCompletion {
    param([int]$TimeoutSeconds = 300)
    
    Write-Info 'Esperando que el workflow inicial complete...'
    Write-Info "Timeout configurado: $TimeoutSeconds segundos"
    
    $startTime = Get-Date
    $checkInterval = 10
    $spinChars = @([char]0x2588, [char]0x2593, [char]0x2592, [char]0x2591)
    $spinIndex = 0
    
    while ($true) {
        $elapsed = ((Get-Date) - $startTime).TotalSeconds
        
        if ($elapsed -gt $TimeoutSeconds) {
            Write-Host
            Write-Warning "Timeout alcanzado despues de $TimeoutSeconds segundos"
            return $false
        }
        
        try {
            $runsJson = gh run list --limit 1 --json status,conclusion,name 2>$null
            
            if ($runsJson) {
                $runs = $runsJson | ConvertFrom-Json
                
                if ($runs.Count -gt 0) {
                    $latestRun = $runs[0]
                    $status = $latestRun.status
                    $conclusion = $latestRun.conclusion
                    $name = $latestRun.name
                    
                    $remainingTime = [math]::Round($TimeoutSeconds - $elapsed)
                    $spinChar = $spinChars[$spinIndex % 4]
                    $spinIndex++
                    
                    $progressMsg = "    $spinChar Workflow: $status (${remainingTime}s restantes)    "
                    Write-Host "`r$progressMsg" -NoNewline -ForegroundColor Gray
                    
                    if ($status -eq 'completed') {
                        Write-Host
                        if ($conclusion -eq 'success') {
                            Write-Success "Workflow completado exitosamente"
                            return $true
                        }
                        elseif ($conclusion -eq 'failure') {
                            Write-Warning 'Workflow fallo - revisar en GitHub Actions'
                            return $true
                        }
                        else {
                            Write-Warning "Workflow completo con estado: $conclusion"
                            return $true
                        }
                    }
                }
            }
        }
        catch {
            # Ignorar errores de polling
        }
        
        Start-Sleep -Seconds $checkInterval
    }
    
    return $false
}

function Set-BranchProtection {
    param(
        [string]$BranchName,
        [string]$RepoName,
        [bool]$AdminEnforcement,
        [int]$Approvals
    )
    
    $protection = @{
        required_status_checks = @{
            strict = $true
            contexts = @('Quality Check')
        }
        enforce_admins = $AdminEnforcement
        required_pull_request_reviews = @{
            dismiss_stale_reviews = $true
            require_code_owner_reviews = $false
            required_approving_review_count = $Approvals
        }
        restrictions = $null
        allow_force_pushes = $false
        allow_deletions = $false
        required_conversation_resolution = $true
    }
    
    $jsonPayload = $protection | ConvertTo-Json -Depth 10
    
    try {
        $apiPath = "repos/:owner/$RepoName/branches/$BranchName/protection"
        $result = $jsonPayload | gh api $apiPath --method PUT --input - 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Proteccion aplicada a $BranchName"
            return $true
        }
        else {
            Write-Error "Fallo aplicando proteccion a $BranchName"
            Write-Info $result
            return $false
        }
    }
    catch {
        Write-Error "Error aplicando proteccion a ${BranchName}: $_"
        return $false
    }
}

function New-GitHubEnvironment {
    param(
        [string]$RepoName,
        [string]$EnvironmentName
    )
    
    try {
        $apiPath = "repos/:owner/$RepoName/environments/$EnvironmentName"
        gh api $apiPath --method PUT 2>$null | Out-Null
        Write-Success "Environment $EnvironmentName creado"
        return $true
    }
    catch {
        Write-Warning "No se pudo crear environment $EnvironmentName"
        return $false
    }
}

function Test-BranchProtectionAvailable {
    param(
        [string]$RepoName
    )
    
    # Si es repo público, siempre está disponible
    if ($Visibility -eq 'public') {
        return $true
    }
    
    # Para repos privados, verificar el plan de la organización o usuario
    if ($Organization) {
        # Verificar plan de la organización
        try {
            $orgInfo = gh api "orgs/$Organization" --jq '.plan.name' 2>$null
            if (-not $orgInfo -or $orgInfo -eq 'free') {
                Write-Warning 'Repositorio privado en organizacion con plan Free detectado'
                Write-Info 'Branch protection rules requieren GitHub Team o Enterprise para repos privados'
                Write-Info 'Mas info: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches'
                return $false
            }
        }
        catch {
            Write-Warning 'No se pudo verificar el plan de la organizacion'
            return $false
        }
    }
    else {
        # Verificar plan del usuario
        try {
            $userPlan = gh api "user" --jq '.plan.name' 2>$null
            if (-not $userPlan -or $userPlan -eq 'free') {
                Write-Warning 'Repositorio privado en cuenta con plan Free detectado'
                Write-Info 'Branch protection rules requieren GitHub Pro para repos privados'
                Write-Info 'Mas info: https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches'
                return $false
            }
        }
        catch {
            Write-Warning 'No se pudo verificar el plan del usuario'
            return $false
        }
    }
    
    return $true
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCRIPT PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

try {
    Clear-Host
    Write-Banner
    Write-Config
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 0: Verificar prerequisitos
    # ───────────────────────────────────────────────────────────────────────────
    if (-not (Test-Prerequisites)) {
        Write-Divider
        Write-Host
        Write-Host ' PREREQUISITOS NO CUMPLIDOS - PROCESO ABORTADO ' -BackgroundColor Red -ForegroundColor White
        Write-Host
        exit 1
    }
    
    Write-Divider
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 1: Crear estructura Salesforce
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Generando estructura Salesforce' -StepNumber 1
    
    # Ejecutar sf project generate (capturar output pero no fallar por warnings)
    try {
        $sfOutput = sf project generate --name $ProjectName --template standard 2>&1 | Out-String
        Write-Host $sfOutput -ForegroundColor Gray
    }
    catch {
        # Ignorar errores aquí, verificaremos si el proyecto se creó
    }
    
    # Verificar que el proyecto se creó correctamente
    $projectFile = Join-Path -Path $ProjectName -ChildPath 'sfdx-project.json'
    
    if (-not (Test-Path $projectFile)) {
        throw "Error generando proyecto Salesforce: el archivo sfdx-project.json no fue creado"
    }
    
    Set-Location $ProjectName
    Write-Success "Proyecto creado en ./$ProjectName"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 2: Configurar README
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Configurando README.md' -StepNumber 2
    
    $readmeTemplatePath = Join-Path -Path $script:ScriptDir -ChildPath 'templates' | Join-Path -ChildPath 'README.md'
    
    if (Test-Path $readmeTemplatePath) {
        Copy-Item -Path $readmeTemplatePath -Destination 'README.md' -Force
        Write-Success 'README.md corporativo aplicado'
    }
    else {
        $readmeLines = @(
            "# $ProjectName"
            ''
            'Proyecto Salesforce generado con VANTEGRATE CI/CD Pipeline.'
            ''
            '## Estructura'
            ''
            '- `force-app/` - Codigo fuente Salesforce'
            '- `.github/workflows/` - Pipelines CI/CD'
            ''
            '## Branches'
            ''
            '- `master` - Produccion (protegida)'
            '- `develop` - Desarrollo (protegida)'
            '- `feature/*` - Features en desarrollo'
            ''
            '## Configuracion Requerida'
            ''
            'Configurar los siguientes secretos en GitHub:'
            ''
            '- `SFDX_AUTH_URL_DEV` - Auth URL del org de desarrollo'
            '- `SFDX_AUTH_URL_PROD` - Auth URL del org de produccion'
        )
        
        if ($IncludeSlackIntegration) {
            $readmeLines += '- `SLACK_WEBHOOK_URL` - Webhook de Slack'
        }
        
        $readmeLines += @(
            ''
            '## Obtener SFDX Auth URL'
            ''
            '```bash'
            'sf org display --verbose --target-org TU_ORG'
            '```'
        )
        
        $readmeLines | Out-File -FilePath 'README.md' -Encoding UTF8
        Write-Success 'README.md default creado'
    }
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 3: Configurar .gitignore
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Configurando .gitignore' -StepNumber 3
    
    $gitignoreLines = @(
        ''
        '# Salesforce'
        '.sfdx/'
        '.sf/'
        '.localdevserver/'
        'deploy-options.json'
        ''
        '# IDE'
        '.vscode/'
        '!.vscode/extensions.json'
        '!.vscode/settings.json'
        '.idea/'
        '*.sublime-*'
        '*.swp'
        '*.swo'
        ''
        '# Dependencies'
        'node_modules/'
        'package-lock.json'
        ''
        '# Build and Coverage'
        'coverage/'
        'dist/'
        '.nyc_output/'
        'junit-reports/'
        'test-results/'
        ''
        '# Auth and Secrets - NEVER COMMIT'
        'auth*.txt'
        '*auth*.json'
        '*.key'
        '*.pem'
        '.env'
        '.env.*'
        ''
        '# OS'
        '.DS_Store'
        '.DS_Store?'
        '._*'
        'Thumbs.db'
        'desktop.ini'
        ''
        '# Logs'
        '*.log'
        'npm-debug.log*'
    )
    
    $gitignoreLines | Add-Content -Path '.gitignore'
    Write-Success '.gitignore configurado'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 4: Configurar workflows CI/CD
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Configurando workflows CI/CD' -StepNumber 4
    
    $workflowPath = Join-Path -Path '.github' -ChildPath 'workflows'
    New-Item -Path $workflowPath -ItemType Directory -Force | Out-Null
    
    $pipelineTemplatePath = Join-Path -Path $script:ScriptDir -ChildPath 'templates' | Join-Path -ChildPath 'pipeline.yml'
    
    if (Test-Path $pipelineTemplatePath) {
        Copy-Item -Path $pipelineTemplatePath -Destination (Join-Path -Path $workflowPath -ChildPath 'pipeline.yml') -Force
        Write-Success 'Pipeline CI/CD configurado'
    }
    else {
        Write-Warning 'Template pipeline.yml no encontrado - crear manualmente'
    }
    
    # Copiar Slack si esta habilitado
    if ($IncludeSlackIntegration) {
        $slackTemplatePath = Join-Path -Path $script:ScriptDir -ChildPath 'templates' | Join-Path -ChildPath 'slack.yml'
        
        if (Test-Path $slackTemplatePath) {
            Copy-Item -Path $slackTemplatePath -Destination (Join-Path -Path $workflowPath -ChildPath 'slack.yml') -Force
            Write-Success 'Integracion Slack configurada'
        }
        else {
            Write-Warning 'Template slack.yml no encontrado'
        }
    }
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 5: Configurar VS Code
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Configurando VS Code' -StepNumber 5
    
    $vscodePath = '.vscode'
    New-Item -Path $vscodePath -ItemType Directory -Force | Out-Null
    
    $vscodeSettings = @{
        'editor.formatOnSave' = $true
        'editor.tabSize' = 4
        'salesforcedx-vscode-core.show-cli-success-msg' = $false
        'files.exclude' = @{
            '**/.sfdx' = $true
            '**/.sf' = $true
        }
    }
    
    $vscodeSettings | ConvertTo-Json -Depth 3 | Out-File -FilePath (Join-Path -Path $vscodePath -ChildPath 'settings.json') -Encoding UTF8
    
    $vscodeExtensions = @{
        recommendations = @(
            'salesforce.salesforcedx-vscode'
            'salesforce.salesforcedx-vscode-apex'
            'salesforce.salesforcedx-vscode-lwc'
            'redhat.vscode-xml'
            'dbaeumer.vscode-eslint'
        )
    }
    
    $vscodeExtensions | ConvertTo-Json -Depth 2 | Out-File -FilePath (Join-Path -Path $vscodePath -ChildPath 'extensions.json') -Encoding UTF8
    
    Write-Success 'VS Code configurado con extensiones recomendadas'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 6: Inicializar Git
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Inicializando repositorio Git' -StepNumber 6
    
    # Configurar git para evitar warnings de CRLF (solo para este repo)
    git init --initial-branch=master
    git config core.autocrlf true
    git config core.safecrlf false
    git config advice.statusHints false
    
    # Agregar y commitear silenciando todos los warnings
    git add . 2>&1 | Out-Null
    git commit -m 'feat: initial commit - Salesforce project with CI/CD pipeline'  2>&1 | Out-Null
    
    Write-Success 'Repositorio Git inicializado con rama master'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 7: Crear repositorio en GitHub
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Creando repositorio en GitHub' -StepNumber 7
    
    
    # Determinar nombre del repo (con o sin organizacion)
    $repoFullName = if ($Organization) { "$Organization/$ProjectName" } else { $ProjectName }
    
    # Crear repo sin push
    $repoOutput = gh repo create $repoFullName --$Visibility --source=. --remote=origin 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Fallo al crear repositorio en GitHub'
        Write-Info "Detalle: $repoOutput"
        throw "Error creando repositorio: $repoOutput"
    }
    
    $repoLocation = if ($Organization) { "organizacion $Organization" } else { 'cuenta personal' }
    Write-Success "Repositorio $Visibility creado en $repoLocation"
    
    # Push manual con mejor manejo de errores
    Write-Info 'Subiendo codigo...'
    $pushOutput = git push -u origin master 
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error 'Fallo al subir codigo a GitHub'
        Write-Info "Detalle: $pushOutput"
        throw "Error en push: $pushOutput"
    }
    
    Write-Success 'Codigo subido a GitHub'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 8: Crear rama develop
    # ───────────────────────────────────────────────────────────────────────────
    Write-Step -Message 'Configurando rama develop' -StepNumber 8
    
    git checkout -b develop 
    git push -u origin develop 
    git checkout master 
    
    Write-Success 'Rama develop creada y publicada'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 9: Crear GitHub Environments
    # ───────────────────────────────────────────────────────────────────────────
    #Write-Step -Message 'Creando GitHub Environments' -StepNumber 9
    
    #New-GitHubEnvironment -RepoName $ProjectName -EnvironmentName 'development'
    #New-GitHubEnvironment -RepoName $ProjectName -EnvironmentName 'production'
    
    #Write-Info 'Configurar reviewers para production manualmente en GitHub'
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 10: Invitar colaboradores
    # ───────────────────────────────────────────────────────────────────────────
    if ($Collaborators.Count -gt 0) {
        Write-Step -Message 'Invitando colaboradores' -StepNumber 10
        
        foreach ($user in $Collaborators) {
            try {
                $apiPath = "repos/:owner/$ProjectName/collaborators/$user"
                gh api $apiPath --method PUT -f permission=push 2>$null | Out-Null
                Write-Success "Invitacion enviada a: $user"
            }
            catch {
                Write-Warning "No se pudo invitar a: $user"
            }
        }
    }
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 11: Esperar workflow y aplicar proteccion
    # ───────────────────────────────────────────────────────────────────────────
    if (-not $SkipBranchProtection) {
        Write-Step -Message 'Verificando disponibilidad de branch protection' -StepNumber 11
        
        if (Test-BranchProtectionAvailable -RepoName $ProjectName) {
            Write-Step -Message 'Esperando workflow inicial' -StepNumber 12
            Write-Info 'Necesario para que GitHub reconozca los status checks'
            
            Start-Sleep -Seconds 15
            
            $workflowOk = Wait-ForWorkflowCompletion -TimeoutSeconds $WaitForWorkflowTimeout
            
            if (-not $workflowOk) {
                Write-Warning 'No se confirmo la ejecucion del workflow'
                Write-Info 'La proteccion de ramas puede fallar'
            }
            
            Write-Step -Message 'Aplicando proteccion de ramas' -StepNumber 13
            
            Set-BranchProtection -BranchName 'master' -RepoName $ProjectName -AdminEnforcement $EnforceAdmins -Approvals $RequiredApprovals
            Set-BranchProtection -BranchName 'develop' -RepoName $ProjectName -AdminEnforcement $EnforceAdmins -Approvals $RequiredApprovals
        }
        else {
            Write-Info 'Omitiendo proteccion de ramas debido a limitaciones del plan'
        }
    }
    else {
        Write-Step -Message 'Proteccion de ramas omitida' -StepNumber 11
        Write-Info 'Usar -SkipBranchProtection:$false para habilitarla'
    }
    
    # ───────────────────────────────────────────────────────────────────────────
    # RESUMEN FINAL
    # ───────────────────────────────────────────────────────────────────────────
    $endTime = Get-Date
    $duration = ($endTime - $script:StartTime).TotalSeconds
    
    Write-Divider
    Write-Host
    
    if ($script:HasErrors) {
        Write-Host ' PROYECTO CONFIGURADO CON ADVERTENCIAS ' -BackgroundColor Yellow -ForegroundColor Black
    }
    else {
        Write-Host ' PROYECTO CONFIGURADO EXITOSAMENTE ' -BackgroundColor Green -ForegroundColor Black
    }
    
    Write-Host
    
    # Obtener URL del repositorio
    $repoOwner = if ($Organization) { $Organization } else { gh api user --jq '.login' 2>$null }
    $repoUrl = "https://github.com/$repoOwner/$ProjectName"
    
    $border = [string]::new([char]0x2500, 58)
    
    Write-Host ([char]0x250C + $border + [char]0x2510) -ForegroundColor Cyan
    Write-Host ([char]0x2502 + '  REPOSITORIO'.PadRight(58) + [char]0x2502) -ForegroundColor Cyan
    Write-Host ([char]0x2502 + "  $repoUrl".PadRight(58) + [char]0x2502) -ForegroundColor White
    Write-Host ([char]0x2514 + $border + [char]0x2518) -ForegroundColor Cyan
    
    Write-Host
    Write-Host '  PROXIMOS PASOS:' -ForegroundColor Yellow
    Write-Host
    Write-Host '  1. Configurar secreto SFDX_AUTH_URL_DEV en GitHub Secrets' -ForegroundColor Gray
    Write-Host '  2. Configurar secreto SFDX_AUTH_URL_PROD en GitHub Secrets' -ForegroundColor Gray
    
    $nextStep = 3
    if ($IncludeSlackIntegration) {
        Write-Host "  $nextStep. Configurar secreto SLACK_WEBHOOK_URL en GitHub Secrets" -ForegroundColor Gray
        $nextStep++
    }
    
    Write-Host "  $nextStep. Configurar reviewers para environment production" -ForegroundColor Gray
    
    Write-Host
    Write-Host '  OBTENER SFDX AUTH URL:' -ForegroundColor Cyan
    Write-Host '  sf org display --verbose --target-org <alias>' -ForegroundColor Gray
    Write-Host
    
    $durationFormatted = [math]::Round($duration, 1)
    Write-Host "  Tiempo total: $durationFormatted segundos" -ForegroundColor DarkGray
    Write-Host
}
catch {
    Write-Host
    Write-Host ' ERROR FATAL ' -BackgroundColor Red -ForegroundColor White
    Write-Host
    Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
    Write-Host
    Write-Host "  Linea: $($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor DarkRed
    Write-Host
    
    # Volver al directorio padre si estamos dentro del proyecto
    $currentPath = (Get-Location).Path
    if ($currentPath -like "*$ProjectName*") {
        Set-Location ..
        Write-Host '  Regresando al directorio padre...' -ForegroundColor Yellow
    }
    
    exit 1
}
