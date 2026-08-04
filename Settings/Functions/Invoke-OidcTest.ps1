function Invoke-OidcTest {
    <#
        The full OIDC verification flow, steps 0 through 11. Reaches UI
        controls ($StartTestButton, $TestProgressBar, etc) through script
        scope, the same way the other functions do. Called by the Start
        Test button click handler in the main script.
    #>
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
}
