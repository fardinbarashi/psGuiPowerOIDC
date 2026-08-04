function Update-ResultsJson {
    $ResultsTextBox.Text = $script:Results | ConvertTo-Json -Depth 20
    Update-UI
}
