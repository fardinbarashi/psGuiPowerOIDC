# PowerOIDC

![](https://raw.githubusercontent.com/fardinbarashi/psGuiPowerOIDC/refs/heads/main/githubRepoContentDeleteIfYouWant/IMG/oidclogo.png)

PowerOIDC is a local PowerShell/XAML tool for testing OpenID Connect (OIDC) flows from a Windows client.
The tool was created for environments where external online OIDC testing tools are not always available or appropriate to use, for example due to strict network rules, firewall restrictions, customer security policies, or isolated environments.
Instead of relying on web-based tools, PowerOIDC runs locally and helps validate the most common parts of an OIDC integration directly from the client machine.

## Features
PowerOIDC can help test and inspect:
```
- OIDC discovery metadata
- JWKS endpoint availability
- Authorization URL generation
- Authorization Code Flow
- Manual authorization code handling
- Token endpoint exchange
- ID token decoding
- ID token header and claims
- UserInfo endpoint
- Refresh token flow
- Refreshed ID token claims
- Refreshed UserInfo response
- Optional old refresh token reuse check
- JSON export of test results
```
## Why this tool exists
In many customer environments, using public online OIDC debugging tools is not possible. The client network may block external services, or security policies may prevent sending configuration details, tokens, or identity-related data to third-party websites.
PowerOIDC was built to make troubleshooting easier in those situations.
It allows the user to run the OIDC test locally, keep the test data inside the environment, and export structured JSON output for further analysis.

## How it works
PowerOIDC uses a graphical interface built with PowerShell and WPF.
The user provides the required OIDC configuration:
```
- Client ID
- Client Secret
- Issuer URL
- Redirect URI
- Scope
```
The tool then performs a step-by-step validation of the OIDC flow.
For the authorization step, PowerOIDC supports a manual flow. The tool opens the authorization URL in the browser. After login, the user copies the redirected URL containing the authorization code and pastes it back into the application.
This avoids the need for the tool to run a local HTTP listener, which can be blocked or restricted in some environments.

## Screenshots
### 1. Configuration
![Configuration](https://raw.githubusercontent.com/fardinbarashi/psGuiPowerOIDC/refs/heads/main/githubRepoContentDeleteIfYouWant/IMG/1.jpg)

### 2. Test view
![Test view](https://raw.githubusercontent.com/fardinbarashi/psGuiPowerOIDC/refs/heads/main/githubRepoContentDeleteIfYouWant/IMG/2.jpg)

### 3. Manual authorization flow
![Manual authorization flow](https://raw.githubusercontent.com/fardinbarashi/psGuiPowerOIDC/refs/heads/main/githubRepoContentDeleteIfYouWant/IMG/2.1.jpg)

### 4. Results
![Results](https://raw.githubusercontent.com/fardinbarashi/psGuiPowerOIDC/refs/heads/main/githubRepoContentDeleteIfYouWant/IMG/3.jpg)

## Requirements
Recommended:
- Windows
- PowerShell 7.x
Minimum:
- Windows PowerShell 5.1

## Configuration
The tool expects configuration files under the `Settings` folder.
Example structure:

```text
PowerOIDC/
├── PowerOIDC.ps1
├── Settings/
│   ├── appconfig.json
│   └── oidcConfig.json
└── Logs/
```

Example `oidcConfig.json`:

```json
{
  "configclientid": "your-client-id",
  "configclientsecret": "your-client-secret",
  "configissuer": "https://your-issuer.example.com",
  "configredirecturi": "http://localhost:44300/signin-oidc",
  "configscopetext1": "openid profile"
}
```

## Usage
1. Clone or download the repository.
2. Update the OIDC configuration in the GUI or in `Settings/oidcConfig.json`.
3. Run the script:
```powershell
./PowerOIDC.ps1
```
4. Open the **Configuration** tab and verify the values.
5. Go to the **Test** tab.
6. Click **Start Full Test**.
7. When the browser opens, sign in to the OIDC provider.
8. After login, copy the full redirected URL from the browser address bar.
9. Paste the URL back into the PowerOIDC dialog.
10. Review the test results in the GUI.
11. Export the result as JSON if needed.

## Manual authorization code flow
During the authorization step, the browser may redirect to a local URL such as:
```text
http://localhost:44300/signin-oidc?code=AUTHORIZATION_CODE&state=STATE_VALUE
```
If no local web server is listening, the browser may show an error page. That is expected.
The important part is the URL in the browser address bar. Copy the full URL and paste it into PowerOIDC.
PowerOIDC will extract:
- `code`
- `state`
- `error`
- `error_description`
If the full redirect URL is provided, the tool can also validate that the returned `state` matches the generated state value.

## Test steps
The test flow includes the following sections:
```
1. Configuration validation
2. Discovery endpoint test
3. JWKS endpoint test
4. Authorization URL generation
5. Manual browser login and authorization code capture
6. Token exchange
7. ID token decoding and claim validation
8. UserInfo endpoint test
9. Refresh token test
10. Refreshed ID token decoding
11. UserInfo test with refreshed access token
12. Old refresh token reuse test
```
## Output
PowerOIDC stores the test results in memory during the run and displays the output in the **Results** tab.
The output can be copied or exported as JSON.
The JSON output may include:
```
- Discovery response
- JWKS response
- Token response
- ID token header
- ID token claims
- UserInfo claims
- Refresh token response
- Refreshed ID token claims
- Refreshed UserInfo claims
```
## Security notes
```
The tool may display sensitive data such as:
- Client secrets
- Authorization codes
- Access tokens
- ID tokens
- Refresh tokens
- User claims
```

## License

Add your preferred license here, for example MIT, Apache-2.0, or a private/internal-use license.
