#!/bin/bash

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  VANTEGRATE - Salesforce Project Generator with CI/CD Pipeline           ║
# ║  Version: 3.0.0 (Bash)                                                    ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

set -e

# ═══════════════════════════════════════════════════════════════════════════════
# VARIABLES GLOBALES
# ═══════════════════════════════════════════════════════════════════════════════

# Obtener el directorio donde está el script (no el directorio de trabajo actual)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROJECT_NAME=""
ORGANIZATION=""
COLLABORATORS=()
VISIBILITY="public"
ENFORCE_ADMINS=false
REQUIRED_APPROVALS=1
WAIT_FOR_WORKFLOW_TIMEOUT=300
INCLUDE_SLACK_INTEGRATION=false
SKIP_BRANCH_PROTECTION=false
HAS_ERRORS=false
START_TIME=$(date +%s)

# ═══════════════════════════════════════════════════════════════════════════════
# COLORES Y SIMBOLOS
# ═══════════════════════════════════════════════════════════════════════════════

# Detectar soporte de colores
if [[ -t 1 ]] && [[ -n "$(tput colors 2>/dev/null)" ]] && [[ "$(tput colors)" -ge 8 ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    WHITE='\033[1;37m'
    GRAY='\033[0;90m'
    DARKGRAY='\033[0;90m'
    NC='\033[0m' # No Color
    BOLD='\033[1m'
    BG_RED='\033[41m'
    BG_GREEN='\033[42m'
    BG_YELLOW='\033[43m'
else
    RED=''
    GREEN=''
    YELLOW=''
    CYAN=''
    MAGENTA=''
    WHITE=''
    GRAY=''
    DARKGRAY=''
    NC=''
    BOLD=''
    BG_RED=''
    BG_GREEN=''
    BG_YELLOW=''
fi

# Símbolos Unicode
CHECKMARK="✔"
CROSS="✘"
WARNING_SIGN="⚠"
BULLET="•"
ARROW="▶"

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE AYUDA
# ═══════════════════════════════════════════════════════════════════════════════

show_help() {
    cat << EOF
VANTEGRATE - Salesforce Project Generator with CI/CD Pipeline

Uso: ./setup.sh -n <nombre_proyecto> [opciones]

Opciones requeridas:
  -n, --name              Nombre del proyecto (requerido)

Opciones:
  -o, --organization      Organizacion de GitHub (si no se especifica, usa cuenta personal)
  -c, --collaborators     Lista de colaboradores separados por coma
  -v, --visibility        Visibilidad del repo: public o private (default: public)
  -e, --enforce-admins    Aplicar reglas de protección también a admins
  -a, --approvals         Número de aprobaciones requeridas (default: 1)
  -t, --timeout           Timeout para esperar workflow en segundos (default: 300)
  -s, --slack             Incluir integración con Slack
  --skip-protection       Omitir protección de ramas
  -h, --help              Mostrar esta ayuda

Ejemplos:
  ./setup.sh -n MiProyecto
  ./setup.sh -n MiProyecto -o Vantegrate -v private
  ./setup.sh -n MiProyecto -o Vantegrate -c "usuario1,usuario2" -a 2 -s

EOF
    exit 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE LOGGING
# ═══════════════════════════════════════════════════════════════════════════════

write_banner() {
    local width=60
    local line=$(printf '═%.0s' $(seq 1 $width))
    
    echo ""
    echo -e "${MAGENTA}╔${line}╗${NC}"
    printf "${MAGENTA}║${NC}  VANTEGRATE - Salesforce Project Generator%*s${MAGENTA}║${NC}\n" $((width - 43)) ""
    printf "${MAGENTA}║${NC}  Version 3.0.0 (Bash)%*s${MAGENTA}║${NC}\n" $((width - 23)) ""
    echo -e "${MAGENTA}╚${line}╝${NC}"
    echo ""
}

write_config() {
    local border=$(printf '─%.0s' $(seq 1 58))
    
    local org_display="Personal"
    if [[ -n "$ORGANIZATION" ]]; then
        org_display="$ORGANIZATION"
    fi
    
    local collab_list="Ninguno"
    if [[ ${#COLLABORATORS[@]} -gt 0 ]]; then
        collab_list=$(IFS=', '; echo "${COLLABORATORS[*]}")
    fi
    
    local slack_status="Deshabilitado"
    if [[ "$INCLUDE_SLACK_INTEGRATION" == true ]]; then
        slack_status="Habilitado"
    fi
    
    echo -e "${DARKGRAY}┌${border}┐${NC}"
    printf "${DARKGRAY}│${NC}  CONFIGURACION%*s${DARKGRAY}│${NC}\n" 43 ""
    echo -e "${DARKGRAY}├${border}┤${NC}"
    
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Proyecto:" "$PROJECT_NAME"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Organizacion:" "$org_display"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Visibilidad:" "$VISIBILITY"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Rama principal:" "master"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Colaboradores:" "$collab_list"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Slack:" "$slack_status"
    printf "${DARKGRAY}│${NC}${GRAY}  %-22s${NC}${WHITE}%-33s${NC}${DARKGRAY}│${NC}\n" "Aprobaciones requeridas:" "$REQUIRED_APPROVALS"
    
    echo -e "${DARKGRAY}└${border}┘${NC}"
    echo ""
}

write_step() {
    local message="$1"
    local step_number="$2"
    local timestamp=$(date '+%H:%M:%S')
    
    echo ""
    echo -e "${CYAN}${ARROW} PASO ${step_number} ${DARKGRAY}│${NC} ${WHITE}${message}${NC} ${DARKGRAY}[${timestamp}]${NC}"
}

write_success() {
    local message="$1"
    echo -e "    ${GREEN}${CHECKMARK} ${message}${NC}"
}

write_warning() {
    local message="$1"
    echo -e "    ${YELLOW}${WARNING_SIGN} ${message}${NC}"
}

write_error() {
    local message="$1"
    echo -e "    ${RED}${CROSS} ${message}${NC}"
    HAS_ERRORS=true
}

write_info() {
    local message="$1"
    echo -e "    ${DARKGRAY}${BULLET}${NC} ${GRAY}${message}${NC}"
}

write_divider() {
    echo ""
    echo -e "${DARKGRAY}$(printf '─%.0s' $(seq 1 60))${NC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE VALIDACION
# ═══════════════════════════════════════════════════════════════════════════════

command_exists() {
    command -v "$1" &> /dev/null
}

test_prerequisites() {
    write_step "Verificando prerequisitos" 0
    
    local all_good=true
    
    # Verificar Git
    if command_exists git; then
        local git_version=$(git --version 2>/dev/null)
        write_success "Git instalado: $git_version"
    else
        write_error "Git no esta instalado"
        write_info "Descargar desde: https://git-scm.com/"
        all_good=false
    fi
    
    # Verificar GitHub CLI
    if command_exists gh; then
        local gh_version=$(gh --version 2>/dev/null | head -1)
        write_success "GitHub CLI instalado: $gh_version"
        
        # Verificar autenticación
        if gh auth status &>/dev/null; then
            write_success "GitHub CLI autenticado correctamente"
        else
            write_error "GitHub CLI no autenticado"
            write_info "Ejecutar: gh auth login"
            all_good=false
        fi
    else
        write_error "GitHub CLI no esta instalado"
        write_info "Descargar desde: https://cli.github.com/"
        all_good=false
    fi
    
    # Verificar Salesforce CLI
    if command_exists sf; then
        local sf_version=$(sf --version 2>/dev/null | head -1)
        write_success "Salesforce CLI instalado: $sf_version"
    else
        write_error "Salesforce CLI no esta instalado"
        write_info "Ejecutar: npm install -g @salesforce/cli"
        all_good=false
    fi
    
    # Verificar que el directorio no exista
    if [[ -d "$PROJECT_NAME" ]]; then
        write_error "El directorio $PROJECT_NAME ya existe localmente"
        write_info "Eliminar el directorio o usar otro nombre"
        all_good=false
    fi
    
    # Verificar templates
    local templates_path="$SCRIPT_DIR/templates"
    if [[ -d "$templates_path" ]]; then
        write_success "Directorio templates encontrado"
    else
        write_warning "Directorio templates no encontrado - se usaran valores por defecto"
    fi
    
    if [[ "$all_good" == true ]]; then
        return 0
    else
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# FUNCIONES DE WORKFLOW
# ═══════════════════════════════════════════════════════════════════════════════

wait_for_workflow_completion() {
    local timeout_seconds="${1:-300}"
    
    write_info "Esperando que el workflow inicial complete..."
    write_info "Timeout configurado: $timeout_seconds segundos"
    
    local start_time=$(date +%s)
    local check_interval=10
    local spin_chars=('█' '▓' '▒' '░')
    local spin_index=0
    
    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ $elapsed -gt $timeout_seconds ]]; then
            echo ""
            write_warning "Timeout alcanzado despues de $timeout_seconds segundos"
            return 1
        fi
        
        local runs_json=$(gh run list --limit 1 --json status,conclusion,name 2>/dev/null || echo "")
        
        if [[ -n "$runs_json" ]] && [[ "$runs_json" != "[]" ]]; then
            local status=$(echo "$runs_json" | grep -o '"status":"[^"]*"' | head -1 | cut -d'"' -f4)
            local conclusion=$(echo "$runs_json" | grep -o '"conclusion":"[^"]*"' | head -1 | cut -d'"' -f4)
            
            local remaining_time=$((timeout_seconds - elapsed))
            local spin_char="${spin_chars[$((spin_index % 4))]}"
            spin_index=$((spin_index + 1))
            
            printf "\r    %s Workflow: %s (%ds restantes)    " "$spin_char" "$status" "$remaining_time"
            
            if [[ "$status" == "completed" ]]; then
                echo ""
                if [[ "$conclusion" == "success" ]]; then
                    write_success "Workflow completado exitosamente"
                    return 0
                elif [[ "$conclusion" == "failure" ]]; then
                    write_warning "Workflow fallo - revisar en GitHub Actions"
                    return 0
                else
                    write_warning "Workflow completo con estado: $conclusion"
                    return 0
                fi
            fi
        fi
        
        sleep $check_interval
    done
    
    return 1
}

set_branch_protection() {
    local branch_name="$1"
    local repo_name="$2"
    local admin_enforcement="$3"
    local approvals="$4"
    
    local protection_json=$(cat << EOF
{
    "required_status_checks": {
        "strict": true,
        "contexts": ["Quality Check"]
    },
    "enforce_admins": $admin_enforcement,
    "required_pull_request_reviews": {
        "dismiss_stale_reviews": true,
        "require_code_owner_reviews": false,
        "required_approving_review_count": $approvals
    },
    "restrictions": null,
    "allow_force_pushes": false,
    "allow_deletions": false,
    "required_conversation_resolution": true
}
EOF
)
    
    local api_path="repos/:owner/$repo_name/branches/$branch_name/protection"
    
    if echo "$protection_json" | gh api "$api_path" --method PUT --input - &>/dev/null; then
        write_success "Proteccion aplicada a $branch_name"
        return 0
    else
        write_error "Fallo aplicando proteccion a $branch_name"
        return 1
    fi
}

new_github_environment() {
    local repo_name="$1"
    local environment_name="$2"
    
    local api_path="repos/:owner/$repo_name/environments/$environment_name"
    
    if gh api "$api_path" --method PUT &>/dev/null; then
        write_success "Environment $environment_name creado"
        return 0
    else
        write_warning "No se pudo crear environment $environment_name"
        return 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# PARSEO DE ARGUMENTOS
# ═══════════════════════════════════════════════════════════════════════════════

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -n|--name)
                PROJECT_NAME="$2"
                shift 2
                ;;
            -o|--organization)
                ORGANIZATION="$2"
                shift 2
                ;;
            -c|--collaborators)
                IFS=',' read -ra COLLABORATORS <<< "$2"
                shift 2
                ;;
            -v|--visibility)
                if [[ "$2" == "public" || "$2" == "private" ]]; then
                    VISIBILITY="$2"
                else
                    echo "Error: visibility debe ser 'public' o 'private'"
                    exit 1
                fi
                shift 2
                ;;
            -e|--enforce-admins)
                ENFORCE_ADMINS=true
                shift
                ;;
            -a|--approvals)
                REQUIRED_APPROVALS="$2"
                shift 2
                ;;
            -t|--timeout)
                WAIT_FOR_WORKFLOW_TIMEOUT="$2"
                shift 2
                ;;
            -s|--slack)
                INCLUDE_SLACK_INTEGRATION=true
                shift
                ;;
            --skip-protection)
                SKIP_BRANCH_PROTECTION=true
                shift
                ;;
            -h|--help)
                show_help
                ;;
            *)
                echo "Opción desconocida: $1"
                echo "Usa --help para ver las opciones disponibles"
                exit 1
                ;;
        esac
    done
    
    # Validar nombre del proyecto
    if [[ -z "$PROJECT_NAME" ]]; then
        echo "Error: El nombre del proyecto es requerido (-n o --name)"
        echo "Usa --help para ver las opciones disponibles"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# SCRIPT PRINCIPAL
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    parse_arguments "$@"
    
    clear
    write_banner
    write_config
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 0: Verificar prerequisitos
    # ───────────────────────────────────────────────────────────────────────────
    if ! test_prerequisites; then
        write_divider
        echo ""
        echo -e "${BG_RED}${WHITE} PREREQUISITOS NO CUMPLIDOS - PROCESO ABORTADO ${NC}"
        echo ""
        exit 1
    fi
    
    write_divider
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 1: Crear estructura Salesforce
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Generando estructura Salesforce" 1
    
    # Ejecutar sf project generate (ignorar warnings en stderr)
    sf project generate --name "$PROJECT_NAME" --template standard || true
    
    # Verificar que el proyecto se creó correctamente
    if [[ ! -d "$PROJECT_NAME" ]] || [[ ! -f "$PROJECT_NAME/sfdx-project.json" ]]; then
        write_error "Error generando proyecto Salesforce"
        exit 1
    fi
    
    cd "$PROJECT_NAME"
    write_success "Proyecto creado en ./$PROJECT_NAME"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 2: Configurar README
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Configurando README.md" 2
    
    local readme_template_path="$SCRIPT_DIR/templates/README.md"
    
    if [[ -f "$readme_template_path" ]]; then
        cp "$readme_template_path" "README.md"
        write_success "README.md corporativo aplicado"
    else
        cat > README.md << EOF
# $PROJECT_NAME

Proyecto Salesforce generado con VANTEGRATE CI/CD Pipeline.

## Estructura

- \`force-app/\` - Codigo fuente Salesforce
- \`.github/workflows/\` - Pipelines CI/CD

## Branches

- \`master\` - Produccion (protegida)
- \`develop\` - Desarrollo (protegida)
- \`feature/*\` - Features en desarrollo

## Configuracion Requerida

Configurar los siguientes secretos en GitHub:

- \`SFDX_AUTH_URL_DEV\` - Auth URL del org de desarrollo
- \`SFDX_AUTH_URL_PROD\` - Auth URL del org de produccion
EOF
        
        if [[ "$INCLUDE_SLACK_INTEGRATION" == true ]]; then
            echo "- \`SLACK_WEBHOOK_URL\` - Webhook de Slack" >> README.md
        fi
        
        cat >> README.md << 'EOF'

## Obtener SFDX Auth URL

```bash
sf org display --verbose --target-org TU_ORG
```
EOF
        
        write_success "README.md default creado"
    fi
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 3: Configurar .gitignore
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Configurando .gitignore" 3
    
    cat >> .gitignore << 'EOF'

# Salesforce
.sfdx/
.sf/
.localdevserver/
deploy-options.json

# IDE
.vscode/
!.vscode/extensions.json
!.vscode/settings.json
.idea/
*.sublime-*
*.swp
*.swo

# Dependencies
node_modules/
package-lock.json

# Build and Coverage
coverage/
dist/
.nyc_output/
junit-reports/
test-results/

# Auth and Secrets - NEVER COMMIT
auth*.txt
*auth*.json
*.key
*.pem
.env
.env.*

# OS
.DS_Store
.DS_Store?
._*
Thumbs.db
desktop.ini

# Logs
*.log
npm-debug.log*
EOF
    
    write_success ".gitignore configurado"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 4: Configurar workflows CI/CD
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Configurando workflows CI/CD" 4
    
    local workflow_path=".github/workflows"
    mkdir -p "$workflow_path"
    
    local pipeline_template_path="$SCRIPT_DIR/templates/pipeline.yml"
    
    if [[ -f "$pipeline_template_path" ]]; then
        cp "$pipeline_template_path" "$workflow_path/pipeline.yml"
        write_success "Pipeline CI/CD configurado"
    else
        write_warning "Template pipeline.yml no encontrado - crear manualmente"
    fi
    
    # Copiar Slack si está habilitado
    if [[ "$INCLUDE_SLACK_INTEGRATION" == true ]]; then
        local slack_template_path="$SCRIPT_DIR/templates/slack.yml"
        
        if [[ -f "$slack_template_path" ]]; then
            cp "$slack_template_path" "$workflow_path/slack.yml"
            write_success "Integracion Slack configurada"
        else
            write_warning "Template slack.yml no encontrado"
        fi
    fi
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 5: Configurar VS Code
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Configurando VS Code" 5
    
    local vscode_path=".vscode"
    mkdir -p "$vscode_path"
    
    cat > "$vscode_path/settings.json" << 'EOF'
{
    "editor.formatOnSave": true,
    "editor.tabSize": 4,
    "salesforcedx-vscode-core.show-cli-success-msg": false,
    "files.exclude": {
        "**/.sfdx": true,
        "**/.sf": true
    }
}
EOF
    
    cat > "$vscode_path/extensions.json" << 'EOF'
{
    "recommendations": [
        "salesforce.salesforcedx-vscode",
        "salesforce.salesforcedx-vscode-apex",
        "salesforce.salesforcedx-vscode-lwc",
        "redhat.vscode-xml",
        "dbaeumer.vscode-eslint"
    ]
}
EOF
    
    write_success "VS Code configurado con extensiones recomendadas"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 6: Inicializar Git
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Inicializando repositorio Git" 6
    
    # Configurar git para evitar warnings de CRLF (solo para este repo)
    git init --initial-branch=master
    git config core.autocrlf input
    git config core.safecrlf false
    git config advice.statusHints false
    
    # Agregar y commitear
    git add . 2>&1 > /dev/null
    git commit -m "feat: initial commit - Salesforce project with CI/CD pipeline" 2>&1 > /dev/null
    
    write_success "Repositorio Git inicializado con rama master"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 7: Crear repositorio en GitHub
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Creando repositorio en GitHub" 7
    
    # Determinar nombre del repo (con o sin organizacion)
    local repo_full_name="$PROJECT_NAME"
    if [[ -n "$ORGANIZATION" ]]; then
        repo_full_name="$ORGANIZATION/$PROJECT_NAME"
    fi
    
    # Crear repo sin push
    if ! gh repo create "$repo_full_name" --"$VISIBILITY" --source=. --remote=origin 2>&1; then
        write_error "Fallo al crear repositorio en GitHub"
        exit 1
    fi
    
    local repo_location="cuenta personal"
    if [[ -n "$ORGANIZATION" ]]; then
        repo_location="organizacion $ORGANIZATION"
    fi
    write_success "Repositorio $VISIBILITY creado en $repo_location"
    
    # Push manual
    write_info "Subiendo codigo..."
    if ! git push -u origin master 2>&1; then
        write_error "Fallo al subir codigo a GitHub"
        exit 1
    fi
    
    write_success "Codigo subido a GitHub"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 8: Crear rama develop
    # ───────────────────────────────────────────────────────────────────────────
    write_step "Configurando rama develop" 8
    
    git checkout -b develop 2>&1 > /dev/null
    git push -u origin develop 2>&1 > /dev/null
    git checkout master 2>&1 > /dev/null
    
    write_success "Rama develop creada y publicada"
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 9: Invitar colaboradores
    # ───────────────────────────────────────────────────────────────────────────
    if [[ ${#COLLABORATORS[@]} -gt 0 ]]; then
        write_step "Invitando colaboradores" 9
        
        for user in "${COLLABORATORS[@]}"; do
            local api_path="repos/:owner/$PROJECT_NAME/collaborators/$user"
            if gh api "$api_path" --method PUT -f permission=push &>/dev/null; then
                write_success "Invitacion enviada a: $user"
            else
                write_warning "No se pudo invitar a: $user"
            fi
        done
    fi
    
    # ───────────────────────────────────────────────────────────────────────────
    # PASO 10: Esperar workflow y aplicar protección
    # ───────────────────────────────────────────────────────────────────────────
    if [[ "$SKIP_BRANCH_PROTECTION" == false ]]; then
        write_step "Esperando workflow inicial" 10
        write_info "Necesario para que GitHub reconozca los status checks"
        
        sleep 15
        
        if ! wait_for_workflow_completion "$WAIT_FOR_WORKFLOW_TIMEOUT"; then
            write_warning "No se confirmo la ejecucion del workflow"
            write_info "La proteccion de ramas puede fallar"
        fi
        
        write_step "Aplicando proteccion de ramas" 11
        
        set_branch_protection "master" "$PROJECT_NAME" "$ENFORCE_ADMINS" "$REQUIRED_APPROVALS"
        set_branch_protection "develop" "$PROJECT_NAME" "$ENFORCE_ADMINS" "$REQUIRED_APPROVALS"
    else
        write_step "Proteccion de ramas omitida" 10
        write_info "Usar sin --skip-protection para habilitarla"
    fi
    
    # ───────────────────────────────────────────────────────────────────────────
    # RESUMEN FINAL
    # ───────────────────────────────────────────────────────────────────────────
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    write_divider
    echo ""
    
    if [[ "$HAS_ERRORS" == true ]]; then
        echo -e "${BG_YELLOW}${WHITE} PROYECTO CONFIGURADO CON ADVERTENCIAS ${NC}"
    else
        echo -e "${BG_GREEN}${WHITE} PROYECTO CONFIGURADO EXITOSAMENTE ${NC}"
    fi
    
    echo ""
    
    # Obtener URL del repositorio
    local repo_owner="$ORGANIZATION"
    if [[ -z "$repo_owner" ]]; then
        repo_owner=$(gh api user --jq '.login' 2>/dev/null)
    fi
    local repo_url="https://github.com/$repo_owner/$PROJECT_NAME"
    
    local border=$(printf '─%.0s' $(seq 1 58))
    
    echo -e "${CYAN}┌${border}┐${NC}"
    printf "${CYAN}│${NC}  REPOSITORIO%*s${CYAN}│${NC}\n" 45 ""
    printf "${CYAN}│${NC}  ${WHITE}%-54s${NC}  ${CYAN}│${NC}\n" "$repo_url"
    echo -e "${CYAN}└${border}┘${NC}"
    
    echo ""
    echo -e "  ${YELLOW}PROXIMOS PASOS:${NC}"
    echo ""
    echo -e "  ${GRAY}1. Configurar secreto SFDX_AUTH_URL_DEV en GitHub Secrets${NC}"
    echo -e "  ${GRAY}2. Configurar secreto SFDX_AUTH_URL_PROD en GitHub Secrets${NC}"
    
    local next_step=3
    if [[ "$INCLUDE_SLACK_INTEGRATION" == true ]]; then
        echo -e "  ${GRAY}$next_step. Configurar secreto SLACK_WEBHOOK_URL en GitHub Secrets${NC}"
        next_step=$((next_step + 1))
    fi
    
    echo -e "  ${GRAY}$next_step. Configurar reviewers para environment production${NC}"
    
    echo ""
    echo -e "  ${CYAN}OBTENER SFDX AUTH URL:${NC}"
    echo -e "  ${GRAY}sf org display --verbose --target-org <alias>${NC}"
    echo ""
    
    echo -e "  ${DARKGRAY}Tiempo total: ${duration} segundos${NC}"
    echo ""
}

# Manejo de errores
trap 'echo -e "\n${BG_RED}${WHITE} ERROR FATAL ${NC}"; echo -e "\n  ${RED}El script se detuvo debido a un error${NC}"; if [[ -n "$PROJECT_NAME" ]] && [[ "$(pwd)" == *"$PROJECT_NAME"* ]]; then cd ..; echo -e "  ${YELLOW}Regresando al directorio padre...${NC}"; fi; exit 1' ERR

# Ejecutar script principal
main "$@"
