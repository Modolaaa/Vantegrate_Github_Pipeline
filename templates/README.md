# Salesforce CI/CD – Vantegrate Enterprise Ready Pipeline

Este repositorio utiliza un pipeline de **CI/CD profesional para Salesforce**, diseñado para equipos que trabajan con **GitHub + Salesforce CLI**, siguiendo buenas prácticas de **DevOps, control de calidad y gobernanza**.

El objetivo es garantizar:
- Calidad de código constante
- Validaciones automáticas antes de desplegar
- Control estricto de despliegues a Producción
- Evitar fallos en repositorios recién creados

---

## 🧱 Arquitectura General del Pipeline

```
Pull Request
   ↓
Code Quality & Validation
   ↓
Merge
   ↓
Deploy (DEV / PROD con Approval)
```

---

## 🔍 Jobs del Workflow

### 1️⃣ Quality Check
- Corre en `push` y `pull_request`
- Ejecuta Salesforce Code Scanner
- Detecta issues temprano

---

### 2️⃣ Validate Pull Request
- Valida contra DEV o PROD según destino
- Usa `sf project deploy validate`
- No modifica la org

---

### 3️⃣ Deploy a Development
- Solo en `develop`
- Solo si existe `SFDX_AUTH_URL_DEV`
- Evita fallos en repos recién creados

---

### 4️⃣ Deploy a Production (Approval Manual)
- Solo en `main`
- Requiere aprobación manual
- Usa GitHub Environments

---

## 🔐 Secrets requeridos

| Secret | Descripción |
|------|-------------|
| SFDX_AUTH_URL_DEV | Org DEV |
| SFDX_AUTH_URL_PROD | Org PROD |

---

## 🧠 Buenas Prácticas

- Nunca pushear directo a `main`
- Usar Pull Requests
- Revisar validaciones antes de aprobar

---

Pipeline diseñado para **Vantegrate**.
