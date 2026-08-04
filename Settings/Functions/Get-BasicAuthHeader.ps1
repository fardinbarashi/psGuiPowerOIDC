function Get-BasicAuthHeader($clientId, $clientSecret) {
    $pair = "$clientId`:$clientSecret"
    $base64 = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))

    return @{ Authorization = "Basic $base64" }
}
