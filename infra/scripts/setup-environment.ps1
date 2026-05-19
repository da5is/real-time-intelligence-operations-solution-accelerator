#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Preprovision hook: configures azd environment with naming standard.

.DESCRIPTION
    Naming convention: {service-abbreviation}-{purpose}-{region}-{iterable}
    Region: Sweden Central (sec)
    Purpose: rti (Real-Time Intelligence)

    Automatically sets:
    - Azure resource names (Event Hub Namespace, Event Hub, Fabric Capacity)
    - Fabric item names (workspace, eventhouse, dashboard, etc.)
    - Admin identity from the currently signed-in Azure CLI user
    - Deployment region to Sweden Central

.NOTES
    Runs automatically as a preprovision hook during `azd up`.
    Only sets values that are not already configured (won't overwrite manual overrides).
#>

$ErrorActionPreference = "Stop"

function Set-AzdEnvIfEmpty {
    param([string]$Name, [string]$Value)
    $current = azd env get-value $Name 2>$null
    if (-not $current -or $current -eq "") {
        azd env set $Name $Value
        Write-Host "  SET $Name = $Value"
    } else {
        Write-Host "  SKIP $Name (already set: $current)"
    }
}

Write-Host "`n🔧 Preprovision: Applying naming standard (sec-01)" -ForegroundColor Cyan
Write-Host "=" * 60

# --- Retrieve current admin identity ---
Write-Host "`n📋 Retrieving signed-in Azure CLI user..." -ForegroundColor Yellow
$userJson = az ad signed-in-user show --query "{upn: userPrincipalName, email: mail}" -o json 2>$null
if ($LASTEXITCODE -ne 0 -or -not $userJson) {
    Write-Warning "Could not retrieve signed-in user. Admin-related values will use defaults."
    $adminUpn = ""
} else {
    $currentUser = $userJson | ConvertFrom-Json
    $adminUpn = $currentUser.upn
    Write-Host "  Admin UPN: $adminUpn" -ForegroundColor Green
}

# --- Azure deployment region ---
Write-Host "`n🌍 Region configuration..." -ForegroundColor Yellow
Set-AzdEnvIfEmpty "AZURE_LOCATION" "swedencentral"

# --- Azure resource name overrides (Bicep-level) ---
# Naming: {abbreviation}-{purpose}-{region}-{iterable}
# Note: Fabric Capacity only allows lowercase alphanumeric (no hyphens)
Write-Host "`n🏗️  Azure resource names..." -ForegroundColor Yellow
Set-AzdEnvIfEmpty "AZURE_EVENT_HUB_NAMESPACE_NAME_OVERRIDE" "evhns-rti-sec-01"
Set-AzdEnvIfEmpty "AZURE_EVENT_HUB_NAME_OVERRIDE" "evh-rti-sec-01"
Set-AzdEnvIfEmpty "AZURE_FABRIC_CAPACITY_NAME_OVERRIDE" "fcrtisec01"

# --- Fabric item names ---
Write-Host "`n📝 Fabric resource names..." -ForegroundColor Yellow
Set-AzdEnvIfEmpty "FABRIC_WORKSPACE_NAME" "ws-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_EVENTHOUSE_NAME" "evh-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_EVENTHOUSE_DATABASE_NAME" "kqldb-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_EVENT_HUB_CONNECTION_NAME" "ehconn-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_RTIDASHBOARD_NAME" "rtidash-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_EVENTSTREAM_NAME" "es-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_ACTIVATOR_NAME" "act-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_DATA_AGENT_NAME" "dagent-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_DATA_AGENT_CONFIGURATION_FOLDER_NAME" "folder-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_DATA_AGENT_CONFIGURATION_ENVIRONMENT_NAME" "env-rti-sec-01"
Set-AzdEnvIfEmpty "FABRIC_DATA_AGENT_CONFIGURATION_NOTEBOOK_NAME" "nb-rti-sec-01"

# --- Admin identity ---
if ($adminUpn) {
    Write-Host "`n👤 Admin configuration..." -ForegroundColor Yellow
    Set-AzdEnvIfEmpty "FABRIC_WORKSPACE_ADMINISTRATORS" $adminUpn
    Set-AzdEnvIfEmpty "FABRIC_ACTIVATOR_ALERTS_EMAIL" $adminUpn
}

Write-Host "`n✅ Preprovision naming configuration complete." -ForegroundColor Green
