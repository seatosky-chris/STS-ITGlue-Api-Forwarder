# Azure Functions profile.ps1
#
# This profile.ps1 will get executed every "cold start" of your Function App.
# "cold start" occurs when:
#
# * A Function App starts up for the very first time
# * A Function App starts up after being de-allocated due to inactivity
#
# You can define helper functions, run commands, or specify environment variables
# NOTE: any variables defined that are not environment variables will get reset after the first execution

# Authenticate with Azure PowerShell using MSI.
# Remove this if you are not planning on using MSI or Azure PowerShell.

# Load the whitelist YAML
$yamlPath = Join-Path $PSScriptRoot "whitelisted-endpoints.yml"
if (Test-Path $yamlPath) {
    if (-not (Get-Command 'ConvertFrom-Yaml' -errorAction SilentlyContinue)) {
        Import-Module powershell-yaml -Function ConvertFrom-Yaml
    }
    Write-Host "Loading and parsing whitelisted-endpoints.yml into global cache variable for this worker instance..." -ForegroundColor Green
    $global:EndpointsCache = Get-Content -Raw $yamlPath | ConvertFrom-Yaml -Ordered
    Remove-Module powershell-yaml -ErrorAction SilentlyContinue
}

# Load the OrgList csv
$csvPath = Join-Path $PSScriptRoot "AzGlueForwarder\OrgList.csv"
if (Test-Path $csvPath) {
    Write-Host "Loading OrgList.csv into global cache variable for this worker instance..." -ForegroundColor Green
    $global:OrgListCache = Import-Csv $csvPath -Delimiter ","
}

# Uncomment the next line to enable legacy AzureRm alias in Azure PowerShell.
# Enable-AzureRmAlias

# You can also define functions or aliases that can be referenced in any of your PowerShell functions.
