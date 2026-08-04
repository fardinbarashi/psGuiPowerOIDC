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
