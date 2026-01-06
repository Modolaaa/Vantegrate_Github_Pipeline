# Salesforce CI/CD Pipeline - Vantegrate Enterprise Ready

Pipeline de **CI/CD profesional para Salesforce**, diseñado para equipos que trabajan con **GitHub + Salesforce CLI**, siguiendo buenas prácticas de DevOps, control de calidad y gobernanza.

---

## Características

- **Quality Gate automático** con Salesforce Code Scanner
- **Validación de PRs** contra la org destino antes del merge
- **Deploy automático** a Development en cada merge a `develop`
- **Deploy controlado** a Production con aprobación manual
- **Branch Protection** configurado automáticamente
- **Setup en un comando** - crea proyecto, repo, ramas y protecciones

---

## Arquitectura del Pipeline

```
feature-branch
       │
       ▼ (Pull Request)
   ┌───────────────────────────────────────┐
   │         Quality Check                 │
   │   (Salesforce Code Scanner)           │
   └───────────────────────────────────────┘
                   │
                   ▼
   ┌───────────────────────────────────────┐
   │         Validate PR                   │
   │   (sf project deploy validate)        │
   │   Target: DEV org o PROD org          │
   └───────────────────────────────────────┘
                   │
                   ▼ (Merge)
           ┌──────┴──────┐
           │             │
           ▼             ▼
       develop         main
           │             │
           ▼             ▼
   ┌─────────────┐ ┌─────────────────┐
   │ Deploy DEV  │ │  Deploy PROD    │
   │ (Automático)│ │ (Con Approval)  │
   └─────────────┘ └─────────────────┘
```

---

## Requisitos Previos

Antes de ejecutar el script, asegurate de tener instalado:

```powershell
# Salesforce CLI
sf --version

# GitHub CLI (autenticado)
gh auth status

# Si no estás autenticado
gh auth login
```

---

## Uso Rápido

### 1. Clonar este repositorio

```powershell
git clone https://github.com/Modolaaa/Vantegrate_Github_Pipeline.git
cd Vantegrate_Github_Pipeline
```

### 2. Ejecutar el script

```powershell
.\setup.ps1 -ProjectName "NombreDelProyecto"
```

El script automáticamente:

1. Genera la estructura del proyecto Salesforce
2. Configura el pipeline CI/CD
3. Crea el repositorio en GitHub
4. Configura las ramas `main` y `develop`
5. Espera la ejecución inicial del workflow
6. Aplica las reglas de protección de ramas

### 3. Configurar los Secrets en GitHub

Una vez completado el script, configurá los secrets de autenticación:

1. Ir a **Settings** → **Secrets and variables** → **Actions**
2. Click en **New repository secret**
3. Agregar los siguientes secrets:

| Secret | Descripción |
|--------|-------------|
| `SFDX_AUTH_URL_DEV` | Auth URL de la org de desarrollo |
| `SFDX_AUTH_URL_PROD` | Auth URL de la org de producción |

### 4. Configurar Environment de Producción (Recomendado)

Para requerir aprobación manual antes del deploy a producción:

1. Ir a **Settings** → **Environments**
2. Click en **New environment**
3. Nombre: `production`
4. Activar **Required reviewers**
5. Agregar los usuarios que deben aprobar
6. Guardar

---

## Obtener el SFDX Auth URL

El Auth URL es necesario para que GitHub Actions pueda autenticarse contra tus orgs de Salesforce.

```bash
# Conectar a la org (si no está conectada)
sf org login web --alias MiOrgDev --set-default

# Obtener el Auth URL
sf org display --verbose --target-org MiOrgDev
```

Buscá la línea **"Sfdx Auth Url"** en el output. Es un string que comienza con `force://`.

**⚠️ Importante:** Este URL contiene credenciales sensibles. Nunca lo compartas ni lo subas a un repositorio.

---

## Jobs del Workflow

### Quality Check

- **Trigger:** Push y Pull Request a `main` o `develop`
- **Acción:** Ejecuta Salesforce Code Scanner
- **Objetivo:** Detectar issues de código temprano

```yaml
sf scanner run --target "force-app" --format table --severity-threshold 2
```

### Validate PR

- **Trigger:** Pull Requests
- **Acción:** Valida el deploy contra la org destino sin ejecutarlo
- **Target:** DEV org (PRs a develop) o PROD org (PRs a main)

```yaml
sf project deploy validate --source-dir force-app --test-level RunLocalTests
```

### Deploy to DEV

- **Trigger:** Push/Merge a `develop`
- **Acción:** Deploy automático a la org de desarrollo
- **Requiere:** Secret `SFDX_AUTH_URL_DEV` configurado

### Deploy to PROD

- **Trigger:** Push/Merge a `main`
- **Acción:** Deploy a producción
- **Requiere:** Secret `SFDX_AUTH_URL_PROD` + Aprobación manual

---

## Estructura del Proyecto Generado

```
MiProyecto/
├── .github/
│   └── workflows/
│       └── pipeline.yml      # Pipeline CI/CD
├── force-app/
│   └── main/
│       └── default/          # Metadata de Salesforce
├── .gitignore
├── README.md
└── sfdx-project.json
```

---

## Flujo de Trabajo Recomendado

### Desarrollo de Features

```bash
# 1. Crear rama desde develop
git checkout develop
git pull origin develop
git checkout -b feature/mi-nueva-feature

# 2. Desarrollar y commitear
git add .
git commit -m "feat: descripción del cambio"

# 3. Subir y crear PR
git push -u origin feature/mi-nueva-feature
# Crear PR en GitHub hacia develop
```

### Release a Producción

```bash
# 1. Crear PR de develop a main
# 2. Esperar validaciones (Quality Check + Validate PR)
# 3. Obtener aprobación del PR
# 4. Merge
# 5. Aprobar el deploy en el environment de producción
```

---

## Solución de Problemas

### Los checks aparecen como "Waiting for status to be reported"

**Causa:** Los status checks fueron configurados antes de que el workflow corriera por primera vez.

**Solución:**
1. Ir a **Settings** → **Branches** → **Branch protection rules**
2. Editar la regla de `main` o `develop`
3. En "Require status checks", eliminar los checks existentes
4. Hacer un push cualquiera para triggear el workflow
5. Una vez completado, volver a agregar los checks: `Quality Check` y `Validate PR`

### El deploy falla por falta de credenciales

**Causa:** Los secrets `SFDX_AUTH_URL_DEV` o `SFDX_AUTH_URL_PROD` no están configurados.

**Solución:** Seguir los pasos de la sección "Configurar los Secrets en GitHub".

### El scanner no encuentra archivos

**Causa:** El directorio `force-app` está vacío o no existe.

**Solución:** El pipeline maneja esto automáticamente creando una estructura mínima. Si persiste, verificá que tu metadata esté en `force-app/main/default/`.

---

## Personalización

### Cambiar el nivel de severidad del scanner

En `pipeline.yml`, modificar el parámetro `--severity-threshold`:

```yaml
sf scanner run --target "force-app" --severity-threshold 3
```

| Valor | Severidad mínima reportada |
|-------|---------------------------|
| 1 | Critical |
| 2 | High (default) |
| 3 | Medium |
| 4 | Low |

### Cambiar el nivel de tests en deploy

En `pipeline.yml`, modificar `--test-level`:

```yaml
sf project deploy start --source-dir force-app --test-level RunLocalTests
```

| Valor | Descripción |
|-------|-------------|
| NoTestRun | Sin tests (solo sandbox) |
| RunSpecifiedTests | Tests específicos |
| RunLocalTests | Tests locales (default) |
| RunAllTestsInOrg | Todos los tests |

### Agregar colaboradores automáticamente

En `setup.ps1`, modificar el array `$Collaborators`:

```powershell
$Collaborators = @("usuario1", "usuario2", "usuario3")
```

---

## Buenas Prácticas

1. **Nunca pushear directo a `main`** - Siempre usar Pull Requests
2. **Revisar las validaciones** antes de aprobar un PR
3. **Mantener los tests actualizados** - El pipeline corre `RunLocalTests`
4. **Rotar los Auth URLs** periódicamente por seguridad
5. **Usar environments** para controlar quién puede deployar a producción

---

## Licencia

Este proyecto es propiedad de **Vantegrate**.

---

## Soporte

Para reportar issues o solicitar features, crear un issue en este repositorio.
