function Decode-Jwt($jwt) {
    $parts = $jwt.Split(".")

    if ($parts.Count -ne 3) { throw "Token is not a JWT with 3 parts" }

    return [PSCustomObject]@{
        Header  = ConvertFrom-Base64UrlJson $parts[0]
        Payload = ConvertFrom-Base64UrlJson $parts[1]
        Raw     = $jwt
    }
}
