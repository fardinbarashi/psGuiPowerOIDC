<#
System requirements
PSVersion 5.x.x, prefer 7.x.x

About Script :
Author : Fardin Barashi
Title : Power OIDC
Description : Power OIDC for on-prem OIDC verification.

Includes JSON output for:
 - Discovery response
 - JWKS response
 - Token response
 - ID token header
 - ID token claims/payload
 - UserInfo claims
 - Refresh response
 - Refreshed ID token claims
 - Refreshed UserInfo claims

Structure :
    Power_OIDC.ps1                     This file. Loads config, UI, functions, wires events.
    Settings\UI\MainWindow.xaml        The main window as XAML. Contains $($appConfig...)
                                       and $($oidcConfig...) tokens that are filled in from
                                       the config files before the XAML is parsed.
    Settings\Functions\*.ps1           One function per file, dot-sourced below.
    Settings\Config\appconfig.json     All UI text / labels.
    Settings\Config\oidcConfig.json    The saved OIDC connection values.
    Settings\Logs\                      Per-run transcripts.


Version : 3.0
Release day : 2026-07-19
Github Link : https://github.com/fardinbarashi/psGuiPowerOIDC
News : Split into UI / Functions / Config / Logs. XAML and each function moved
       to their own files. Behaviour unchanged.

#>

#------------------------------- Settings -------------------------------

$ErrorActionPreference = 'Stop'

$ScriptName   = $MyInvocation.MyCommand.Name
if (-not $ScriptName) { $ScriptName = 'Power_OIDC.ps1' }

$Script:Root      = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$Script:SettingsPath = Join-Path $Script:Root 'Settings'
$Script:ConfigPath   = Join-Path $Script:SettingsPath 'Config'
$Script:UiPath       = Join-Path $Script:SettingsPath 'UI'
$Script:FuncPath     = Join-Path $Script:SettingsPath 'Functions'
$Script:LogFolder    = Join-Path $Script:SettingsPath 'Logs'

if (-not (Test-Path $Script:LogFolder)) {
    New-Item -Path $Script:LogFolder -ItemType Directory -Force | Out-Null
}

$LogFileDate = Get-Date -Format 'yyyy-MM-dd_HH.mm.ss'

# Load configuration files
$appConfigPath  = Join-Path $Script:ConfigPath 'appconfig.json'
$oidcConfigPath = Join-Path $Script:ConfigPath 'oidcConfig.json'

if (-not (Test-Path $appConfigPath))  { throw "Cannot find appconfig.json at $appConfigPath" }
if (-not (Test-Path $oidcConfigPath)) { throw "Cannot find oidcConfig.json at $oidcConfigPath" }

$appConfig  = Get-Content $appConfigPath  -Raw | ConvertFrom-Json
$oidcConfig = Get-Content $oidcConfigPath -Raw | ConvertFrom-Json

$TranScriptLogFile = Join-Path $Script:LogFolder "$ScriptName - $LogFileDate.txt"
Start-Transcript -Path $TranScriptLogFile -Force | Out-Null
Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
Write-Host '.. Starting TranScript'

# Global results store
$script:Results = [ordered]@{}

#------------------------------- Load Assemblies -------------------------------

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

#------------------------------- Load functions -------------------------------

if (-not (Test-Path $Script:FuncPath)) { throw "Function folder not found: $Script:FuncPath" }

$functionFiles = Get-ChildItem -Path $Script:FuncPath -Filter '*.ps1' -File
if (-not $functionFiles) { throw "No .ps1 files found in $Script:FuncPath" }

foreach ($file in $functionFiles) {
    try   { . $file.FullName }
    catch { throw "Failed to load function file '$($file.Name)': $($_.Exception.Message)" }
}

#------------------------------- Build XAML -------------------------------
$xamlTemplatePath = Join-Path $Script:UiPath 'MainWindow.xaml'
if (-not (Test-Path $xamlTemplatePath)) { throw "Cannot find the UI file: $xamlTemplatePath" }

$xamlRaw = Get-Content $xamlTemplatePath -Raw
$xaml    = $ExecutionContext.InvokeCommand.ExpandString($xamlRaw)

#------------------------------- Start Script -------------------------------

[xml]$xamlDoc = $xaml
$reader  = New-Object System.Xml.XmlNodeReader $xamlDoc
$window  = [Windows.Markup.XamlReader]::Load($reader)

# Get UI controls
$ClientIdInput       = $window.FindName('ClientIdInput')
$ClientSecretInput   = $window.FindName('ClientSecretInput')
$IssuerInput         = $window.FindName('IssuerInput')
$RedirectUriInput    = $window.FindName('RedirectUriInput')
$ScopeInput          = $window.FindName('ScopeInput')

$SaveConfigButton    = $window.FindName('SaveConfigButton')
$ResetButton         = $window.FindName('ResetButton')
$ValidateButton      = $window.FindName('ValidateButton')
$ConfigStatusBorder  = $window.FindName('ConfigStatusBorder')
$ConfigStatusText    = $window.FindName('ConfigStatusText')

$MainTabControl      = $window.FindName('MainTabControl')
$StartTestButton     = $window.FindName('StartTestButton')
$TestProgressText    = $window.FindName('TestProgressText')
$TestProgressDetail  = $window.FindName('TestProgressDetail')
$TestProgressBar     = $window.FindName('TestProgressBar')
$TestResultsPanel    = $window.FindName('TestResultsPanel')

$ResultsTextBox      = $window.FindName('ResultsTextBox')
$CopyAllButton       = $window.FindName('CopyAllButton')
$ExportJsonButton    = $window.FindName('ExportJsonButton')
$ClearResultsButton  = $window.FindName('ClearResultsButton')

#------------------------------- Event Handlers : Config Tab -------------------------------

$SaveConfigButton.Add_Click({
    try {
        $newConfig = [PSCustomObject]@{
            configclientid     = $ClientIdInput.Text
            configclientsecret = $ClientSecretInput.Text
            configissuer       = $IssuerInput.Text
            configredirecturi  = $RedirectUriInput.Text
            configscopetext1   = $ScopeInput.Text
        }

        $newConfig | ConvertTo-Json | Set-Content -Path (Join-Path $Script:ConfigPath "oidcConfig-$LogFileDate.json") -Encoding UTF8 -Force
        $script:oidcConfig = $newConfig

        $ConfigStatusBorder.Background = '#1b5e20'
        $ConfigStatusText.Text         = $appConfig.configstatussaved
        $ConfigStatusBorder.Visibility = 'Visible'
    }
    catch {
        $ConfigStatusBorder.Background = '#b71c1c'
        $ConfigStatusText.Text         = "Error saving config: $($_.Exception.Message)"
        $ConfigStatusBorder.Visibility = 'Visible'
    }
})

$ResetButton.Add_Click({
    $ClientIdInput.Text     = $oidcConfig.configclientid
    $ClientSecretInput.Text = $oidcConfig.configclientsecret
    $IssuerInput.Text       = $oidcConfig.configissuer
    $RedirectUriInput.Text  = $oidcConfig.configredirecturi
    $ScopeInput.Text        = $oidcConfig.configscopetext1

    $ConfigStatusBorder.Background = '#0d47a1'
    $ConfigStatusText.Text         = 'Defaults restored'
    $ConfigStatusBorder.Visibility = 'Visible'
})

$ValidateButton.Add_Click({
    $errors = @()

    if ([string]::IsNullOrWhiteSpace($ClientIdInput.Text))     { $errors += 'Client ID is empty' }
    if ([string]::IsNullOrWhiteSpace($ClientSecretInput.Text)) { $errors += 'Client Secret is empty' }
    if ([string]::IsNullOrWhiteSpace($IssuerInput.Text))       { $errors += 'Issuer is empty' }
    if ([string]::IsNullOrWhiteSpace($RedirectUriInput.Text))  { $errors += 'Redirect URI is empty' }
    if ([string]::IsNullOrWhiteSpace($ScopeInput.Text))        { $errors += 'Scope is empty' }

    if ($errors.Count -eq 0) {
        $ConfigStatusBorder.Background = '#1b5e20'
        $ConfigStatusText.Text         = 'All fields are valid'
    }
    else {
        $ConfigStatusBorder.Background = '#b71c1c'
        $ConfigStatusText.Text         = "Validation failed: $($errors -join ', ')"
    }
    $ConfigStatusBorder.Visibility = 'Visible'
})

#------------------------------- Event Handlers : Results Tab -------------------------------

$CopyAllButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($ResultsTextBox.Text)) {
        [System.Windows.Clipboard]::SetText($ResultsTextBox.Text)
    }
})

$ExportJsonButton.Add_Click({
    $saveDialog            = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter     = 'JSON files (*.json)|*.json|All files (*.*)|*.*'
    $saveDialog.DefaultExt = 'json'
    $saveDialog.FileName   = "OIDC_Results_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"

    if ($saveDialog.ShowDialog() -eq 'OK') {
        $ResultsTextBox.Text | Set-Content -Path $saveDialog.FileName -Encoding UTF8
    }
})

$ClearResultsButton.Add_Click({
    $ResultsTextBox.Text     = $appConfig.resultsplaceholder
    $TestResultsPanel.Children.Clear()
    $TestProgressBar.Value   = 0
    $TestProgressText.Text   = $appConfig.testprogresstext
    $TestProgressDetail.Text = $appConfig.testprogressdetail
    $script:Results          = [ordered]@{}
})

#------------------------------- Event Handlers : Start Test -------------------------------

$StartTestButton.Add_Click({ Invoke-OidcTest })

#------------------------------- Show Window -------------------------------

$window.Add_Closed({ try { Stop-Transcript | Out-Null } catch { } })
$window.ShowDialog() | Out-Null
