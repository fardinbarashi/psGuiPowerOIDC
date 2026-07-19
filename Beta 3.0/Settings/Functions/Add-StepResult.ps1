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
