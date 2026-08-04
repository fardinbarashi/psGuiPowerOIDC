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
