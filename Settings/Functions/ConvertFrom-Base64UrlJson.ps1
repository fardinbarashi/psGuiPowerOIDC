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
