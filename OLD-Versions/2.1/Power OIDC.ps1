<#
System requirements
PSVersion 5.x.x, prefer 7.x.x

About Script :
Author : Fardin Barashi
Title : Power OIDC
Description : Power OIDC for onprem OIDC verifiction 

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

Version : 1.0
Release day : 2026-05-19
Github Link : https://github.com/fardinbarashi
News :

#>

#------------------------------- Settings -------------------------------

# Error-Settings
$ErrorActionPreference = "Stop"

# Transcript
$ScriptName    = $MyInvocation.MyCommand.Name
$LogFileDate   = Get-Date -Format "yyyy-MM-dd_HH.mm.ss"
$LogFolder     = "$PSScriptRoot\Logs\"
$SettingsPath  = "$PSScriptRoot\Settings"

if (-not (Test-Path $LogFolder)) {
    New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
}

# Load configuration files
$appConfig  = Get-Content "$SettingsPath\appconfig.json"  -Raw | ConvertFrom-Json
$oidcConfig = Get-Content "$SettingsPath\oidcConfig.json" -Raw | ConvertFrom-Json


$TranScriptLogFile = "$LogFolder\$ScriptName - $LogFileDate.txt"
$StartTranscript = Start-Transcript -Path $TranScriptLogFile -Force
Get-Date -Format "yyyy/MM/dd HH:mm:ss"
Write-Host ".. Starting TranScript"


# Global results store
$script:Results = [ordered]@{}

#------------------------------- Load Assemblies -------------------------------

[void][System.Reflection.Assembly]::LoadWithPartialName("presentationframework")
[void][System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

#------------------------------- Function List -------------------------------

function ConvertFrom-Base64UrlJson($base64Url) {
    $base64 = $base64Url.Replace("-", "+").Replace("_", "/")

    switch ($base64.Length % 4) {
        2 { $base64 += "==" }
        3 { $base64 += "=" }
        1 { throw "Invalid base64url string" }
    }

    $json = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($base64))
    return $json | ConvertFrom-Json
}

function Decode-Jwt($jwt) {
    $parts = $jwt.Split(".")

    if ($parts.Count -ne 3) { throw "Token is not a JWT with 3 parts" }

    return [PSCustomObject]@{
        Header  = ConvertFrom-Base64UrlJson $parts[0]
        Payload = ConvertFrom-Base64UrlJson $parts[1]
        Raw     = $jwt
    }
}

function Get-BasicAuthHeader($clientId, $clientSecret) {
    $pair = "$clientId`:$clientSecret"
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

    return @{ Authorization = "Basic $base64" }
}

function Get-QueryParameterValue {
    param(
        [string]$InputText,
        [string]$ParameterName
    )

    if ([string]::IsNullOrWhiteSpace($InputText)) {
        return $null
    }

    $value = $InputText.Trim()

    # If user pasted only the authorization code, return it directly for "code".
    if ($ParameterName -eq "code" -and $value -notmatch "[?&=]") {
        return $value
    }

    $pattern = "(^|[?&])$([regex]::Escape($ParameterName))=([^&]+)"
    $match = [regex]::Match($value, $pattern)

    if (-not $match.Success) {
        return $null
    }

    return [System.Net.WebUtility]::UrlDecode($match.Groups[2].Value)
}

function Show-ManualCodeInputDialog {
    param(
        [string]$AuthorizationUrl,
        [System.Windows.Window]$OwnerWindow = $null
    )

    [xml]$dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Manual OIDC Authorization"
        Width="940"
        Height="760"
        MinWidth="900"
        MinHeight="700"
        WindowStartupLocation="CenterScreen"
        ResizeMode="CanResize"
        Background="#181818"
        Foreground="#F5F5F5"
        FontFamily="Segoe UI"
        FontSize="12">

    <Window.Resources>
        <Style x:Key="SectionTitle" TargetType="TextBlock">
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>

        <Style x:Key="MutedText" TargetType="TextBlock">
            <Setter Property="Foreground" Value="#B0BEC5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="TextWrapping" Value="Wrap"/>
        </Style>

        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#2A2A2A"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="16,10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Margin" Value="0,0,10,0"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="8"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center"
                                              VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#3A3A3A"/>
                            </Trigger>
                            <Trigger Property="IsPressed" Value="True">
                                <Setter Property="Background" Value="#1F1F1F"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#424242"/>
                                <Setter Property="Foreground" Value="#9E9E9E"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#0D47A1"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#1565C0"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#0B3D91"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#1B5E20"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2E7D32"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#174D1B"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#B71C1C"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#C62828"/>
                </Trigger>
                <Trigger Property="IsPressed" Value="True">
                    <Setter Property="Background" Value="#8E1616"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#232323"/>
            <Setter Property="Foreground" Value="#F5F5F5"/>
            <Setter Property="BorderBrush" Value="#3F3F46"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="12"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="CaretBrush" Value="White"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="8">
                            <ScrollViewer x:Name="PART_ContentHost"
                                          Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#42A5F5"/>
                            </Trigger>
                            <Trigger Property="IsReadOnly" Value="True">
                                <Setter Property="Foreground" Value="#CFD8DC"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <Grid Margin="24">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="16"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="20"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <Border Grid.Row="0" Background="#202020" CornerRadius="14" Padding="20">
            <Grid>
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="16"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>

                <Border Grid.Column="0" Width="46" Height="46" CornerRadius="12" Background="#0D47A1">
                    <TextBlock Text="OIDC" Foreground="White" FontWeight="Bold" FontSize="11"
                               HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>

                <StackPanel Grid.Column="2">
                    <TextBlock Text="Manual Authorization Code"
                               FontSize="22"
                               FontWeight="Bold"
                               Foreground="White"/>
                    <TextBlock Margin="0,8,0,0"
                               Style="{StaticResource MutedText}"
                               Text="Log in through the browser. Then paste the final redirected URL, or only the authorization code, in the input field below."/>
                </StackPanel>
            </Grid>
        </Border>

        <ScrollViewer Grid.Row="2" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled">
            <StackPanel>
                <Border Background="#1F1F1F" CornerRadius="12" Padding="16" Margin="0,0,0,16">
                    <StackPanel>
                        <TextBlock Style="{StaticResource SectionTitle}" Text="Steps"/>
                        <TextBlock Style="{StaticResource MutedText}" Text="1. Click Open Browser."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="2. Sign in to your OIDC provider."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="3. After login, copy the final redirect URL from the browser address bar."/>
                        <TextBlock Style="{StaticResource MutedText}" Text="4. Paste the final redirect URL below and click OK."/>
                    </StackPanel>
                </Border>

                <TextBlock Style="{StaticResource SectionTitle}" Text="Authorization URL"/>
                <TextBox x:Name="AuthUrlBox"
                         Style="{StaticResource ModernTextBox}"
                         Height="84"
                         IsReadOnly="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Margin="0,0,0,12"/>

                <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
                    <Button x:Name="CopyUrlButton"
                            Content="Copy Auth URL"
                            Style="{StaticResource ModernButton}"
                            Width="150"
                            Height="40"/>

                    <Button x:Name="OpenBrowserButton"
                            Content="Open Browser"
                            Style="{StaticResource PrimaryButton}"
                            Width="150"
                            Height="40"/>

                    <Button x:Name="PasteClipboardButton"
                            Content="Paste Clipboard"
                            Style="{StaticResource ModernButton}"
                            Width="150"
                            Height="40"/>
                </StackPanel>

                <TextBlock Style="{StaticResource SectionTitle}" Text="Paste final redirect URL or authorization code here"/>
                <TextBox x:Name="InputBox"
                         Style="{StaticResource ModernTextBox}"
                         Height="145"
                         AcceptsReturn="True"
                         TextWrapping="Wrap"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Disabled"
                         Margin="0,0,0,14"/>

                <Border Background="#1D2A36" CornerRadius="10" Padding="14" Margin="0,0,0,10">
                    <TextBlock Style="{StaticResource MutedText}"
                               Foreground="#90CAF9"
                               Text="Tip: Do not paste the Authorization URL from the top field. Paste the final URL after login, for example http://localhost:44300/signin-oidc?code=...&amp;state=..."/>
                </Border>

                <Border x:Name="ValidationBorder" Background="#3A1F1F" CornerRadius="10" Padding="14" Visibility="Collapsed">
                    <TextBlock x:Name="ValidationText"
                               Foreground="#FFCDD2"
                               TextWrapping="Wrap"/>
                </Border>
            </StackPanel>
        </ScrollViewer>

        <Grid Grid.Row="4">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="10"/>
                <ColumnDefinition Width="Auto"/>
            </Grid.ColumnDefinitions>

            <Button x:Name="CancelButton"
                    Grid.Column="1"
                    Content="Cancel"
                    Style="{StaticResource DangerButton}"
                    Width="110"
                    Height="42"/>

            <Button x:Name="OkButton"
                    Grid.Column="3"
                    Content="OK"
                    Style="{StaticResource SuccessButton}"
                    Width="110"
                    Height="42"/>
        </Grid>
    </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $dialogXaml
    $dialog = [Windows.Markup.XamlReader]::Load($reader)

    if ($OwnerWindow) {
        $dialog.Owner = $OwnerWindow
        $dialog.WindowStartupLocation = "CenterOwner"
    }

    $AuthUrlBox           = $dialog.FindName("AuthUrlBox")
    $InputBox             = $dialog.FindName("InputBox")
    $CopyUrlButton        = $dialog.FindName("CopyUrlButton")
    $OpenBrowserButton    = $dialog.FindName("OpenBrowserButton")
    $PasteClipboardButton = $dialog.FindName("PasteClipboardButton")
    $OkButton             = $dialog.FindName("OkButton")
    $CancelButton         = $dialog.FindName("CancelButton")
    $ValidationBorder     = $dialog.FindName("ValidationBorder")
    $ValidationText       = $dialog.FindName("ValidationText")

    $AuthUrlBox.Text = $AuthorizationUrl
    $dialog.Tag = $null

    function Set-ManualDialogValidationMessage {
        param([string]$Message)
        $ValidationText.Text = $Message
        $ValidationBorder.Visibility = "Visible"
    }

    $CopyUrlButton.Add_Click({
        [System.Windows.Clipboard]::SetText($AuthorizationUrl)
    })

    $OpenBrowserButton.Add_Click({
        Start-Process $AuthorizationUrl
    })

    $PasteClipboardButton.Add_Click({
        if ([System.Windows.Clipboard]::ContainsText()) {
            $InputBox.Text = [System.Windows.Clipboard]::GetText()
            $InputBox.CaretIndex = $InputBox.Text.Length
            $InputBox.Focus() | Out-Null
            $ValidationBorder.Visibility = "Collapsed"
        }
    })

    $OkButton.Add_Click({
        $inputValue = $InputBox.Text.Trim()

        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            Set-ManualDialogValidationMessage "Paste the final redirected URL or the authorization code before clicking OK."
            return
        }

        if ($inputValue -eq $AuthorizationUrl -or ($inputValue -match "response_type=code" -and $inputValue -notmatch "[?&]code=")) {
            Set-ManualDialogValidationMessage "This looks like the Authorization URL, not the final redirect URL. First complete login in the browser. Then copy the final URL from the browser address bar. It must contain code=..."
            return
        }

        $dialog.Tag = $inputValue
        $dialog.DialogResult = $true
        $dialog.Close()
    })

    $CancelButton.Add_Click({
        $dialog.DialogResult = $false
        $dialog.Close()
    })

    $dialog.Add_ContentRendered({
        $InputBox.Focus() | Out-Null
    })

    $result = $dialog.ShowDialog()

    if (-not $result) {
        throw "Manual login was cancelled"
    }

    return [string]$dialog.Tag
}

function Update-UI {
    # Force UI render to keep the interface responsive
    $window.Dispatcher.Invoke([Action]{}, "Render")
}

function Update-Progress {
    param(
        [int]$Current,
        [int]$Total,
        [string]$Detail
    )

    $TestProgressText.Text   = "$Current / $Total steps completed"
    $TestProgressDetail.Text = $Detail
    $TestProgressBar.Value   = [math]::Round(($Current / $Total) * 100, 0)
    Update-UI
}

function Add-StepResult {
    param(
        [string]$Title,
        [string]$Message,
        [ValidateSet("Success","Error","Warning")]
        [string]$Status = "Success",
        [bool]$HasJsonBadge = $false
    )

    switch ($Status) {
        "Success" { $bgColor = "#1b5e20"; $msgColor = "#c8e6c9" }
        "Error"   { $bgColor = "#b71c1c"; $msgColor = "#ffcdd2" }
        "Warning" { $bgColor = "#ef6c00"; $msgColor = "#ffe0b2" }
    }

    $border               = New-Object System.Windows.Controls.Border
    $border.Background    = $bgColor
    $border.CornerRadius  = New-Object System.Windows.CornerRadius(6)
    $border.Padding       = New-Object System.Windows.Thickness(15)
    $border.Margin        = New-Object System.Windows.Thickness(0, 12, 0, 0)

    $grid = New-Object System.Windows.Controls.Grid

    $col1 = New-Object System.Windows.Controls.ColumnDefinition
    $col2 = New-Object System.Windows.Controls.ColumnDefinition
    $col2.Width = "Auto"
    $grid.ColumnDefinitions.Add($col1) | Out-Null
    $grid.ColumnDefinitions.Add($col2) | Out-Null

    $stack = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($stack, 0)

    $titleBlock              = New-Object System.Windows.Controls.TextBlock
    $titleBlock.Text         = $Title
    $titleBlock.Foreground   = "White"
    $titleBlock.FontWeight   = "Bold"
    $titleBlock.FontSize     = 13
    $titleBlock.TextWrapping = "Wrap"

    $msgBlock              = New-Object System.Windows.Controls.TextBlock
    $msgBlock.Text         = $Message
    $msgBlock.Foreground   = $msgColor
    $msgBlock.FontSize     = 11
    $msgBlock.Margin       = New-Object System.Windows.Thickness(0, 5, 0, 0)
    $msgBlock.TextWrapping = "Wrap"

    $stack.Children.Add($titleBlock) | Out-Null
    $stack.Children.Add($msgBlock) | Out-Null
    $grid.Children.Add($stack) | Out-Null

    if ($HasJsonBadge) {
        $badge              = New-Object System.Windows.Controls.Border
        $badge.Background   = "#4caf50"
        $badge.CornerRadius = New-Object System.Windows.CornerRadius(4)
        $badge.Padding      = New-Object System.Windows.Thickness(8, 4, 8, 4)
        $badge.Margin       = New-Object System.Windows.Thickness(15, 0, 0, 0)
        $badge.VerticalAlignment = "Top"
        [System.Windows.Controls.Grid]::SetColumn($badge, 1)

        $badgeText            = New-Object System.Windows.Controls.TextBlock
        $badgeText.Text       = $appConfig.badgejson
        $badgeText.Foreground = "White"
        $badgeText.FontSize   = 10
        $badgeText.FontWeight = "Bold"
        $badge.Child          = $badgeText
        $grid.Children.Add($badge) | Out-Null
    }

    $border.Child = $grid
    $TestResultsPanel.Children.Add($border) | Out-Null
    Update-UI
}

function Update-ResultsJson {
    $ResultsTextBox.Text = $script:Results | ConvertTo-Json -Depth 20
    Update-UI
}

#------------------------------- Build XAML -------------------------------

$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="$($appConfig.name) - $($appConfig.version)"
        Width="1100"
        Height="750"
        WindowStartupLocation="CenterScreen"
        Background="#1e1e1e"
        Foreground="#e0e0e0"
        FontFamily="Segoe UI"
        FontSize="12"
        ResizeMode="CanResizeWithGrip">

    <Window.Resources>
        <Style x:Key="ModernButton" TargetType="Button">
            <Setter Property="Background" Value="#0d47a1"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="15,10"/>
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Button">
                        <Border Background="{TemplateBinding Background}"
                                CornerRadius="6"
                                Padding="{TemplateBinding Padding}">
                            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#1565c0"/>
                            </Trigger>
                            <Trigger Property="IsEnabled" Value="False">
                                <Setter Property="Background" Value="#424242"/>
                                <Setter Property="Foreground" Value="#9e9e9e"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="SuccessButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#1b5e20"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#2e7d32"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource ModernButton}">
            <Setter Property="Background" Value="#b71c1c"/>
            <Style.Triggers>
                <Trigger Property="IsMouseOver" Value="True">
                    <Setter Property="Background" Value="#c62828"/>
                </Trigger>
            </Style.Triggers>
        </Style>

        <Style x:Key="ModernTextBox" TargetType="TextBox">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="#e0e0e0"/>
            <Setter Property="BorderBrush" Value="#404040"/>
            <Setter Property="BorderThickness" Value="1"/>
            <Setter Property="Padding" Value="10"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TextBox">
                        <Border Background="{TemplateBinding Background}"
                                BorderBrush="{TemplateBinding BorderBrush}"
                                BorderThickness="{TemplateBinding BorderThickness}"
                                CornerRadius="4">
                            <ScrollViewer x:Name="PART_ContentHost" Padding="{TemplateBinding Padding}"/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsFocused" Value="True">
                                <Setter Property="BorderBrush" Value="#0d47a1"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <Style x:Key="TabItemStyle" TargetType="TabItem">
            <Setter Property="Background" Value="#2d2d2d"/>
            <Setter Property="Foreground" Value="#b0bec5"/>
            <Setter Property="BorderThickness" Value="0"/>
            <Setter Property="Padding" Value="20,12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="TabItem">
                        <Grid>
                            <Border Background="{TemplateBinding Background}"
                                    BorderThickness="0,0,0,3"
                                    BorderBrush="Transparent"
                                    Padding="{TemplateBinding Padding}">
                                <ContentPresenter VerticalAlignment="Center"
                                                  HorizontalAlignment="Center"
                                                  ContentSource="Header"
                                                  RecognizesAccessKey="True"/>
                            </Border>
                        </Grid>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsSelected" Value="True">
                                <Setter Property="BorderBrush" Value="#0d47a1"/>
                                <Setter Property="Foreground" Value="White"/>
                                <Setter Property="Background" Value="#363636"/>
                            </Trigger>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter Property="Background" Value="#363636"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>

    <TabControl x:Name="MainTabControl" Background="#1e1e1e" BorderThickness="0">

        <!-- ============================== TAB 1: CONFIGURATION ============================== -->
        <TabItem Header="$($appConfig.configheader1)" Style="{StaticResource TabItemStyle}">
            <ScrollViewer Background="#1e1e1e" VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="40,30,40,30">

                    <TextBlock Text="$($appConfig.configtext1)" FontSize="26" FontWeight="Bold" Foreground="White" Margin="0,0,0,10"/>
                    <TextBlock Text="$($appConfig.configtext2)" Foreground="#90caf9" FontSize="13" Margin="0,0,0,25"/>

                    <Separator Background="#404040" Height="2" Margin="0,0,0,25"/>

                    <!-- Client ID -->
                    <StackPanel Margin="0,0,0,25">
                        <TextBlock Text="$($appConfig.configclientidtext1)" Foreground="#b0bec5" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,8"/>
                        <TextBox x:Name="ClientIdInput" Text="$($oidcConfig.configclientid)" Style="{StaticResource ModernTextBox}" Height="40" Margin="0,0,0,8"/>
                        <TextBlock Text="$($appConfig.configclientidtext2)" Foreground="#757575" FontSize="10" FontStyle="Italic"/>
                    </StackPanel>

                    <!-- Client Secret -->
                    <StackPanel Margin="0,0,0,25">
                        <TextBlock Text="$($appConfig.configclientsecrettext1)" Foreground="#b0bec5" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,8"/>
                        <TextBox x:Name="ClientSecretInput" Text="$($oidcConfig.configclientsecret)" Style="{StaticResource ModernTextBox}" Height="40" Margin="0,0,0,8"/>
                        <TextBlock Text="$($appConfig.configclientsecrettext2)" Foreground="#757575" FontSize="10" FontStyle="Italic"/>
                    </StackPanel>

                    <!-- Issuer -->
                    <StackPanel Margin="0,0,0,25">
                        <TextBlock Text="$($appConfig.configissuertext1)" Foreground="#b0bec5" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,8"/>
                        <TextBox x:Name="IssuerInput" Text="$($oidcConfig.configissuer)" Style="{StaticResource ModernTextBox}" Height="40" Margin="0,0,0,8"/>
                        <TextBlock Text="$($appConfig.configissuertext2)" Foreground="#757575" FontSize="10" FontStyle="Italic"/>
                    </StackPanel>

                    <!-- Redirect URI -->
                    <StackPanel Margin="0,0,0,25">
                        <TextBlock Text="$($appConfig.configredirecturitext1)" Foreground="#b0bec5" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,8"/>
                        <TextBox x:Name="RedirectUriInput" Text="$($oidcConfig.configredirecturi)" Style="{StaticResource ModernTextBox}" Height="40" Margin="0,0,0,8"/>
                        <TextBlock Text="$($appConfig.configredirecturitext2)" Foreground="#757575" FontSize="10" FontStyle="Italic"/>
                    </StackPanel>

                    <!-- Scope -->
                    <StackPanel Margin="0,0,0,30">
                        <TextBlock Text="$($appConfig.configscopetext1)" Foreground="#b0bec5" FontWeight="SemiBold" FontSize="13" Margin="0,0,0,8"/>
                        <TextBox x:Name="ScopeInput" Text="$($oidcConfig.configscopetext1)" Style="{StaticResource ModernTextBox}" Height="40" Margin="0,0,0,8"/>
                        <TextBlock Text="$($appConfig.configscopetext2)" Foreground="#757575" FontSize="10" FontStyle="Italic"/>
                    </StackPanel>

                    <Separator Background="#404040" Height="2" Margin="0,0,0,25"/>

                    <!-- Buttons -->
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Left" Margin="0,0,0,25">
                        <Button x:Name="SaveConfigButton" Content="$($appConfig.configbutton1)" Style="{StaticResource SuccessButton}" Width="200" Height="45" FontSize="13" Margin="0,0,12,0"/>
                        <Button x:Name="ResetButton"      Content="$($appConfig.configbutton2)" Style="{StaticResource ModernButton}"  Width="200" Height="45" FontSize="13" Margin="0,0,12,0"/>
                        <Button x:Name="ValidateButton"   Content="$($appConfig.configbutton3)" Style="{StaticResource ModernButton}"  Width="150" Height="45" FontSize="13"/>
                    </StackPanel>

                    <!-- Status message -->
                    <Border x:Name="ConfigStatusBorder" Background="#1b5e20" CornerRadius="6" Padding="15" Margin="0,20,0,0" Visibility="Collapsed">
                        <TextBlock x:Name="ConfigStatusText" Text="$($appConfig.configstatussaved)" Foreground="White" VerticalAlignment="Center" FontSize="13" FontWeight="SemiBold"/>
                    </Border>

                </StackPanel>
            </ScrollViewer>
        </TabItem>

        <!-- ============================== TAB 2: TEST ============================== -->
        <TabItem Header="$($appConfig.testheader1)" Style="{StaticResource TabItemStyle}">
            <Grid Background="#1e1e1e">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Row="0" Margin="40,25,40,25">

                    <Button x:Name="StartTestButton" Content="$($appConfig.testbutton1)" Style="{StaticResource SuccessButton}" Height="55" FontSize="15" FontWeight="Bold" Margin="0,0,0,20"/>

                    <Border Background="#2d2d2d" CornerRadius="8" Padding="20">
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="*"/>
                                <ColumnDefinition Width="Auto"/>
                            </Grid.ColumnDefinitions>

                            <StackPanel Grid.Column="0">
                                <TextBlock x:Name="TestProgressText"   Text="$($appConfig.testprogresstext)"   Foreground="White"   FontWeight="Bold" FontSize="13"/>
                                <TextBlock x:Name="TestProgressDetail" Text="$($appConfig.testprogressdetail)" Foreground="#90caf9" FontSize="12"/>
                            </StackPanel>

                            <ProgressBar x:Name="TestProgressBar" Grid.Column="1" Width="350" Height="24" Margin="20,0,0,0" Background="#404040" Foreground="#0d47a1" Value="0"/>
                        </Grid>
                    </Border>
                </StackPanel>

                <ScrollViewer Grid.Row="1" Background="#1e1e1e" VerticalScrollBarVisibility="Auto" Margin="40,0,40,40">
                    <StackPanel x:Name="TestResultsPanel"/>
                </ScrollViewer>
            </Grid>
        </TabItem>

        <!-- ============================== TAB 3: RESULTS ============================== -->
        <TabItem Header="$($appConfig.resultsheader1)" Style="{StaticResource TabItemStyle}">
            <Grid Background="#1e1e1e">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>

                <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="40,20,40,0">
                    <Button x:Name="CopyAllButton"   Content="$($appConfig.resultsbutton1)" Style="{StaticResource ModernButton}" Width="150" Height="40" Margin="0,0,10,0"/>
                    <Button x:Name="ExportJsonButton" Content="$($appConfig.resultsbutton2)" Style="{StaticResource ModernButton}" Width="150" Height="40" Margin="0,0,10,0"/>
                    <Button x:Name="ClearResultsButton" Content="$($appConfig.resultsbutton3)" Style="{StaticResource DangerButton}" Width="120" Height="40"/>
                </StackPanel>

                <TextBox x:Name="ResultsTextBox" Grid.Row="1"
                         Style="{StaticResource ModernTextBox}"
                         Background="#2d2d2d"
                         Foreground="#4caf50"
                         FontFamily="Consolas"
                         FontSize="11"
                         TextWrapping="Wrap"
                         IsReadOnly="True"
                         Margin="40,20,40,40"
                         VerticalScrollBarVisibility="Auto"
                         HorizontalScrollBarVisibility="Auto"
                         Text="$($appConfig.resultsplaceholder)"/>
            </Grid>
        </TabItem>

    </TabControl>
</Window>
"@

#------------------------------- Start Script -------------------------------

[xml]$xamlDoc = $xaml
$reader  = New-Object System.Xml.XmlNodeReader $xamlDoc
$window  = [Windows.Markup.XamlReader]::Load($reader)

# Get UI controls
$ClientIdInput       = $window.FindName("ClientIdInput")
$ClientSecretInput   = $window.FindName("ClientSecretInput")
$IssuerInput         = $window.FindName("IssuerInput")
$RedirectUriInput    = $window.FindName("RedirectUriInput")
$ScopeInput          = $window.FindName("ScopeInput")

$SaveConfigButton    = $window.FindName("SaveConfigButton")
$ResetButton         = $window.FindName("ResetButton")
$ValidateButton      = $window.FindName("ValidateButton")
$ConfigStatusBorder  = $window.FindName("ConfigStatusBorder")
$ConfigStatusText    = $window.FindName("ConfigStatusText")

$MainTabControl      = $window.FindName("MainTabControl")
$StartTestButton     = $window.FindName("StartTestButton")
$TestProgressText    = $window.FindName("TestProgressText")
$TestProgressDetail  = $window.FindName("TestProgressDetail")
$TestProgressBar     = $window.FindName("TestProgressBar")
$TestResultsPanel    = $window.FindName("TestResultsPanel")

$ResultsTextBox      = $window.FindName("ResultsTextBox")
$CopyAllButton       = $window.FindName("CopyAllButton")
$ExportJsonButton    = $window.FindName("ExportJsonButton")
$ClearResultsButton  = $window.FindName("ClearResultsButton")

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

        $newConfig | ConvertTo-Json | Set-Content -Path "$SettingsPath\oidcConfig-$LogFileDate.json" -Encoding UTF8 -Force
        $script:oidcConfig = $newConfig

        $ConfigStatusBorder.Background = "#1b5e20"
        $ConfigStatusText.Text         = $appConfig.configstatussaved
        $ConfigStatusBorder.Visibility = "Visible"
    }
    catch {
        $ConfigStatusBorder.Background = "#b71c1c"
        $ConfigStatusText.Text         = "Error saving config: $($_.Exception.Message)"
        $ConfigStatusBorder.Visibility = "Visible"
    }
})

$ResetButton.Add_Click({
    $ClientIdInput.Text     = $oidcConfig.configclientid
    $ClientSecretInput.Text = $oidcConfig.configclientsecret
    $IssuerInput.Text       = $oidcConfig.configissuer
    $RedirectUriInput.Text  = $oidcConfig.configredirecturi
    $ScopeInput.Text        = $oidcConfig.configscopetext1

    $ConfigStatusBorder.Background = "#0d47a1"
    $ConfigStatusText.Text         = "Defaults restored"
    $ConfigStatusBorder.Visibility = "Visible"
})

$ValidateButton.Add_Click({
    $errors = @()

    if ([string]::IsNullOrWhiteSpace($ClientIdInput.Text))     { $errors += "Client ID is empty" }
    if ([string]::IsNullOrWhiteSpace($ClientSecretInput.Text)) { $errors += "Client Secret is empty" }
    if ([string]::IsNullOrWhiteSpace($IssuerInput.Text))       { $errors += "Issuer is empty" }
    if ([string]::IsNullOrWhiteSpace($RedirectUriInput.Text))  { $errors += "Redirect URI is empty" }
    if ([string]::IsNullOrWhiteSpace($ScopeInput.Text))        { $errors += "Scope is empty" }

    if ($errors.Count -eq 0) {
        $ConfigStatusBorder.Background = "#1b5e20"
        $ConfigStatusText.Text         = "All fields are valid"
    }
    else {
        $ConfigStatusBorder.Background = "#b71c1c"
        $ConfigStatusText.Text         = "Validation failed: $($errors -join ', ')"
    }
    $ConfigStatusBorder.Visibility = "Visible"
})

#------------------------------- Event Handlers : Results Tab -------------------------------

$CopyAllButton.Add_Click({
    if (-not [string]::IsNullOrWhiteSpace($ResultsTextBox.Text)) {
        [System.Windows.Clipboard]::SetText($ResultsTextBox.Text)
    }
})

$ExportJsonButton.Add_Click({
    $saveDialog              = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter       = "JSON files (*.json)|*.json|All files (*.*)|*.*"
    $saveDialog.DefaultExt   = "json"
    $saveDialog.FileName     = "OIDC_Results_$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').json"

    if ($saveDialog.ShowDialog() -eq "OK") {
        $ResultsTextBox.Text | Set-Content -Path $saveDialog.FileName -Encoding UTF8
    }
})

$ClearResultsButton.Add_Click({
    $ResultsTextBox.Text = $appConfig.resultsplaceholder
    $TestResultsPanel.Children.Clear()
    $TestProgressBar.Value   = 0
    $TestProgressText.Text   = $appConfig.testprogresstext
    $TestProgressDetail.Text = $appConfig.testprogressdetail
    $script:Results          = [ordered]@{}
})

#------------------------------- Event Handlers : Start Test -------------------------------

$StartTestButton.Add_Click({

    # Reset state
    $TestResultsPanel.Children.Clear()
    $ResultsTextBox.Text   = ""
    $TestProgressBar.Value = 0
    $script:Results        = [ordered]@{}

    $StartTestButton.IsEnabled = $false
    $MainTabControl.SelectedIndex = 1
    Update-UI

    # Read values from UI
    $clientId     = $ClientIdInput.Text
    $clientSecret = $ClientSecretInput.Text
    $issuer       = $IssuerInput.Text
    $redirectUri  = $RedirectUriInput.Text
    $scope        = $ScopeInput.Text
    $discoveryUrl = "$issuer/.well-known/openid-configuration"

    $totalSteps = 12
    $stepNumber = 0

    # ---------------- TEST 0: CONFIG VALIDATION ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 0 : Validating configuration..."

        if ([string]::IsNullOrWhiteSpace($clientId))     { throw "clientId is empty" }
        if ([string]::IsNullOrWhiteSpace($clientSecret)) { throw "clientSecret is empty" }
        if ([string]::IsNullOrWhiteSpace($issuer))       { throw "issuer is empty" }
        if ([string]::IsNullOrWhiteSpace($redirectUri))  { throw "redirectUri is empty" }
        if ([string]::IsNullOrWhiteSpace($scope))        { throw "scope is empty" }

        Add-StepResult -Title "Section 0 : Config validation" -Message "All required values are present" -Status "Success"
    }
    catch {
        Add-StepResult -Title "Section 0 : Config validation" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 1: DISCOVERY ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 1 : Testing discovery endpoint..."

        $discovery = Invoke-RestMethod -Method Get -Uri $discoveryUrl

        if ($discovery.issuer -ne $issuer)                              { throw "issuer mismatch" }
        if ([string]::IsNullOrWhiteSpace($discovery.authorization_endpoint)) { throw "authorization_endpoint missing" }
        if ([string]::IsNullOrWhiteSpace($discovery.token_endpoint))    { throw "token_endpoint missing" }
        if ([string]::IsNullOrWhiteSpace($discovery.jwks_uri))          { throw "jwks_uri missing" }
        if ([string]::IsNullOrWhiteSpace($discovery.userinfo_endpoint)) { throw "userinfo_endpoint missing" }

        $authorizationEndpoint = $discovery.authorization_endpoint
        $tokenEndpoint         = $discovery.token_endpoint
        $userInfoEndpoint      = $discovery.userinfo_endpoint
        $jwksUri               = $discovery.jwks_uri

        $script:Results.discovery = $discovery

        Add-StepResult -Title "Section 1 : Discovery endpoint" -Message "Discovery endpoint works. All required endpoints are present." -Status "Success" -HasJsonBadge $true
        Update-ResultsJson
    }
    catch {
        Add-StepResult -Title "Section 1 : Discovery endpoint" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 2: JWKS ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 2 : Testing JWKS endpoint..."

        $jwks = Invoke-RestMethod -Method Get -Uri $jwksUri

        if (-not $jwks.keys -or $jwks.keys.Count -lt 1) { throw "JWKS contains no keys" }

        $script:Results.jwks = $jwks

        Add-StepResult -Title "Section 2 : JWKS endpoint" -Message "JWKS contains $($jwks.keys.Count) key(s)" -Status "Success" -HasJsonBadge $true
        Update-ResultsJson
    }
    catch {
        Add-StepResult -Title "Section 2 : JWKS endpoint" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 3: BUILD AUTH URL ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 3 : Building authorization URL..."

        $state              = [guid]::NewGuid().ToString()
        $nonce              = [guid]::NewGuid().ToString()
        $encodedRedirectUri = [System.Net.WebUtility]::UrlEncode($redirectUri)
        $encodedScope       = [System.Net.WebUtility]::UrlEncode($scope)

        $authUrl = "$authorizationEndpoint" +
                   "?client_id=$clientId" +
                   "&response_type=code" +
                   "&scope=$encodedScope" +
                   "&redirect_uri=$encodedRedirectUri" +
                   "&state=$state" +
                   "&nonce=$nonce"

        Add-StepResult -Title "Section 3 : Build authorization URL" -Message "Authorization URL built successfully" -Status "Success"
    }
    catch {
        Add-StepResult -Title "Section 3 : Build authorization URL" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 4: MANUAL AUTHORIZATION CODE ----------------
    $code          = $null
    $returnedState = $null

    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 4 : Manual browser login..."

        Add-StepResult `
            -Title "Section 4 : Manual browser login" `
            -Message "Browser will open. After login, copy the redirected URL or authorization code and paste it into the dialog." `
            -Status "Warning"

        Start-Process $authUrl

        $manualInput = Show-ManualCodeInputDialog -AuthorizationUrl $authUrl -OwnerWindow $window

        $code                  = Get-QueryParameterValue -InputText $manualInput -ParameterName "code"
        $returnedState         = Get-QueryParameterValue -InputText $manualInput -ParameterName "state"
        $loginError            = Get-QueryParameterValue -InputText $manualInput -ParameterName "error"
        $loginErrorDescription = Get-QueryParameterValue -InputText $manualInput -ParameterName "error_description"

        if ($loginError) {
            throw "Login failed. error=$loginError error_description=$loginErrorDescription"
        }

        if ([string]::IsNullOrWhiteSpace($code)) {
            if ($manualInput -match "response_type=code" -and $manualInput -notmatch "[?&]code=") {
                throw "You pasted the Authorization URL. Complete the login first, then paste the final redirected URL that contains code=..."
            }
            throw "Authorization code is empty. Paste the full redirected URL after login or paste only the code value."
        }

        # If the full redirected URL was pasted, validate state.
        # If only the code was pasted, state cannot be validated manually.
        if (-not [string]::IsNullOrWhiteSpace($returnedState)) {
            if ($returnedState -ne $state) {
                throw "State mismatch. Expected '$state', got '$returnedState'"
            }
        }
        else {
            Add-StepResult `
                -Title "Section 4 : State validation" `
                -Message "State was not provided because only the authorization code was pasted. Continuing without state validation." `
                -Status "Warning"
        }

        Add-StepResult `
            -Title "Section 4 : Manual authorization code" `
            -Message "Authorization code received manually" `
            -Status "Success"
    }
    catch {
        Add-StepResult `
            -Title "Section 4 : Manual authorization code" `
            -Message "Error: $($_.Exception.Message)" `
            -Status "Error"

        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 5: TOKEN EXCHANGE ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 5 : Exchanging authorization code for tokens..."

        $headers = Get-BasicAuthHeader $clientId $clientSecret
        $tokenResponse = Invoke-RestMethod -Method Post `
            -Uri $tokenEndpoint `
            -Headers $headers `
            -ContentType "application/x-www-form-urlencoded" `
            -Body @{
                grant_type   = "authorization_code"
                code         = $code
                redirect_uri = $redirectUri
            }

        $idToken      = $tokenResponse.id_token
        $accessToken  = $tokenResponse.access_token
        $refreshToken = $tokenResponse.refresh_token

        if ([string]::IsNullOrWhiteSpace($idToken))       { throw "id_token is empty" }
        if ([string]::IsNullOrWhiteSpace($accessToken))   { throw "access_token is empty" }
        if ($tokenResponse.token_type -ne "Bearer")       { throw "token_type is not Bearer" }

        $script:Results.tokenResponse = $tokenResponse

        Add-StepResult -Title "Section 5 : Token exchange" -Message "Tokens received. token_type=Bearer, expires_in=$($tokenResponse.expires_in)" -Status "Success" -HasJsonBadge $true
        Update-ResultsJson
    }
    catch {
        Add-StepResult -Title "Section 5 : Token exchange" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 6: ID TOKEN CLAIMS ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 6 : Decoding id_token..."

        $decodedIdToken = Decode-Jwt $idToken

        $script:Results.idTokenHeader = $decodedIdToken.Header
        $script:Results.idTokenClaims = $decodedIdToken.Payload

        if ($decodedIdToken.Payload.iss -ne $issuer) { throw "id_token iss mismatch" }

        $aud = $decodedIdToken.Payload.aud
        if ($aud -is [System.Array]) {
            if ($clientId -notin $aud) { throw "id_token aud does not contain clientId" }
        }
        else {
            if ($aud -ne $clientId) { throw "id_token aud mismatch" }
        }

        if ($decodedIdToken.Payload.nonce -ne $nonce) { throw "id_token nonce mismatch" }

        $nowUnix = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        if ($decodedIdToken.Payload.exp -le $nowUnix)     { throw "id_token is expired" }
        if ($decodedIdToken.Payload.iat -gt ($nowUnix + 60)) { throw "id_token iat is in the future" }

        if ($decodedIdToken.Header.alg -notin @("RS256", "ES256")) { throw "Unexpected id_token alg: $($decodedIdToken.Header.alg)" }

        $kidStatus = "id_token kid has no value"
        if ($decodedIdToken.Header.kid) {
            $matchingKey = $jwks.keys | Where-Object { $_.kid -eq $decodedIdToken.Header.kid }
            if (-not $matchingKey) { throw "id_token kid not found in JWKS: $($decodedIdToken.Header.kid)" }
            $kidStatus = "kid found in JWKS"
        }

        Add-StepResult -Title "Section 6 : ID token claims" -Message "id_token validated. alg=$($decodedIdToken.Header.alg), $kidStatus" -Status "Success" -HasJsonBadge $true
        Update-ResultsJson
    }
    catch {
        Add-StepResult -Title "Section 6 : ID token claims" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 7: USERINFO ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 7 : Testing UserInfo endpoint..."

        $userInfo = Invoke-RestMethod -Method Get `
            -Uri $userInfoEndpoint `
            -Headers @{ Authorization = "Bearer $accessToken" }

        if ([string]::IsNullOrWhiteSpace($userInfo.sub)) { throw "userinfo sub is empty" }

        $script:Results.userinfo = $userInfo

        Add-StepResult -Title "Section 7 : UserInfo endpoint" -Message "UserInfo received. sub=$($userInfo.sub)" -Status "Success" -HasJsonBadge $true
        Update-ResultsJson
    }
    catch {
        Add-StepResult -Title "Section 7 : UserInfo endpoint" -Message "Error: $($_.Exception.Message)" -Status "Error"
        $StartTestButton.IsEnabled = $true
        return
    }

    # ---------------- TEST 8: REFRESH TOKEN ----------------
    $refreshResponse = $null
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 8 : Testing refresh token..."

        if ([string]::IsNullOrWhiteSpace($refreshToken)) {
            Add-StepResult -Title "Section 8 : Refresh token" -Message "No refresh_token returned by provider, skipping" -Status "Warning"
        }
        else {
            $refreshResponse = Invoke-RestMethod -Method Post `
                -Uri $tokenEndpoint `
                -Headers $headers `
                -ContentType "application/x-www-form-urlencoded" `
                -Body @{
                    grant_type    = "refresh_token"
                    refresh_token = $refreshToken
                }

            if ([string]::IsNullOrWhiteSpace($refreshResponse.id_token))     { throw "new id_token is empty" }
            if ([string]::IsNullOrWhiteSpace($refreshResponse.access_token)) { throw "new access_token is empty" }
            if ($refreshResponse.token_type -ne "Bearer")                    { throw "refresh token_type is not Bearer" }

            $script:Results.refreshResponse = $refreshResponse

            $rotationMsg = if ($refreshResponse.refresh_token -eq $refreshToken) { "WARN: refresh token was not rotated" } else { "Refresh token was rotated" }

            Add-StepResult -Title "Section 8 : Refresh token" -Message "Refresh successful. $rotationMsg" -Status "Success" -HasJsonBadge $true
            Update-ResultsJson
        }
    }
    catch {
        Add-StepResult -Title "Section 8 : Refresh token" -Message "Error: $($_.Exception.Message)" -Status "Error"
    }

    # ---------------- TEST 9: REFRESHED ID TOKEN CLAIMS ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 9 : Decoding refreshed id_token..."

        if ($refreshResponse -and $refreshResponse.id_token) {
            $decodedRefreshIdToken = Decode-Jwt $refreshResponse.id_token
            $script:Results.refreshedIdTokenHeader = $decodedRefreshIdToken.Header
            $script:Results.refreshedIdTokenClaims = $decodedRefreshIdToken.Payload

            Add-StepResult -Title "Section 9 : Refreshed ID token claims" -Message "Refreshed id_token decoded successfully" -Status "Success" -HasJsonBadge $true
            Update-ResultsJson
        }
        else {
            Add-StepResult -Title "Section 9 : Refreshed ID token claims" -Message "Skipped (no refreshed id_token)" -Status "Warning"
        }
    }
    catch {
        Add-StepResult -Title "Section 9 : Refreshed ID token claims" -Message "Error: $($_.Exception.Message)" -Status "Error"
    }

    # ---------------- TEST 10: USERINFO WITH REFRESHED ACCESS TOKEN ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 10 : UserInfo with refreshed access token..."

        if ($refreshResponse -and $refreshResponse.access_token) {
            $refreshedUserInfo = Invoke-RestMethod -Method Get `
                -Uri $userInfoEndpoint `
                -Headers @{ Authorization = "Bearer $($refreshResponse.access_token)" }

            if ($refreshedUserInfo.sub -ne $userInfo.sub) { throw "refreshed userinfo sub mismatch" }

            $script:Results.refreshedUserinfo = $refreshedUserInfo

            Add-StepResult -Title "Section 10 : UserInfo with refreshed access token" -Message "UserInfo verified with refreshed access token" -Status "Success" -HasJsonBadge $true
            Update-ResultsJson
        }
        else {
            Add-StepResult -Title "Section 10 : UserInfo with refreshed access token" -Message "Skipped (no refreshed access token)" -Status "Warning"
        }
    }
    catch {
        Add-StepResult -Title "Section 10 : UserInfo with refreshed access token" -Message "Error: $($_.Exception.Message)" -Status "Error"
    }

    # ---------------- TEST 11: OLD REFRESH TOKEN REUSE ----------------
    try {
        $stepNumber++
        Update-Progress $stepNumber $totalSteps "Section 11 : Testing old refresh token reuse..."

        if ($refreshToken) {
            try {
                $reuseResponse = Invoke-RestMethod -Method Post `
                    -Uri $tokenEndpoint `
                    -Headers $headers `
                    -ContentType "application/x-www-form-urlencoded" `
                    -Body @{
                        grant_type    = "refresh_token"
                        refresh_token = $refreshToken
                    }

                $script:Results.oldRefreshTokenReuse = $reuseResponse

                Add-StepResult -Title "Section 11 : Old refresh token reuse" -Message "WARN: Old refresh token was accepted again. Rotation may not be enforced." -Status "Warning" -HasJsonBadge $true
                Update-ResultsJson
            }
            catch {
                Add-StepResult -Title "Section 11 : Old refresh token reuse" -Message "Old refresh token reuse failed as expected (rotation enforced)" -Status "Success"
            }
        }
        else {
            Add-StepResult -Title "Section 11 : Old refresh token reuse" -Message "Skipped (no refresh token)" -Status "Warning"
        }
    }
    catch {
        Add-StepResult -Title "Section 11 : Old refresh token reuse" -Message "Error: $($_.Exception.Message)" -Status "Error"
    }

    # ---------------- SUMMARY ----------------
    Update-Progress $totalSteps $totalSteps "OIDC test completed"
    Add-StepResult -Title "Summary : OIDC test completed" -Message "All sections executed. See Results tab for full JSON output." -Status "Success"
    Update-ResultsJson

    $StartTestButton.IsEnabled = $true
})

#------------------------------- Show Window -------------------------------

$window.ShowDialog() | Out-Null

# Stop-Transcript
