function Get-AuthCodeViaHttpListener {
    <#
        Automatic authorization-code capture for the "Automatic capture" redirect mode.
        Starts a local HttpListener on the redirect URI, opens the authorization URL in
        the browser, and returns the full redirected URL (containing code/state) once the
        provider redirects back. Mirrors the browser extension's automatic mode.

        Only http://localhost style redirect URIs are supported (no admin rights or TLS
        certificate needed). For https or non-local redirect URIs, use Manual paste.
    #>
    param(
        [Parameter(Mandatory)][string]$AuthorizationUrl,
        [Parameter(Mandatory)][string]$RedirectUri,
        [int]$TimeoutSeconds = 180
    )

    $uri = [System.Uri]$RedirectUri
    if ($uri.Scheme -ne 'http') {
        throw "Automatic capture supports only an http://localhost redirect URI. For '$RedirectUri', use Manual paste or change the redirect URI to http://localhost:<port>/..."
    }

    $prefix = '{0}://{1}:{2}/' -f $uri.Scheme, $uri.Host, $uri.Port

    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add($prefix)

    try {
        $listener.Start()
    }
    catch {
        throw "Could not start the local listener on $prefix. $($_.Exception.Message) Try Manual paste instead."
    }

    try {
        Start-Process $AuthorizationUrl

        $task = $listener.GetContextAsync()
        if (-not $task.Wait([TimeSpan]::FromSeconds($TimeoutSeconds))) {
            throw "Timed out after $TimeoutSeconds seconds waiting for the redirect. Complete the login, or use Manual paste."
        }

        $context = $task.Result
        $fullUrl = $context.Request.Url.AbsoluteUri

        $html  = "<html><head><meta charset='utf-8'></head><body style='font-family:Segoe UI;background:#1e1e1e;color:#e0e0e0;text-align:center;padding-top:60px;'><h2>PowerOIDC</h2><p>Authorization received. You can close this tab and return to PowerOIDC.</p></body></html>"
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($html)
        $context.Response.ContentType     = 'text/html; charset=utf-8'
        $context.Response.ContentLength64 = $bytes.Length
        $context.Response.OutputStream.Write($bytes, 0, $bytes.Length)
        $context.Response.OutputStream.Close()

        return $fullUrl
    }
    finally {
        if ($listener.IsListening) { $listener.Stop() }
        $listener.Close()
    }
}
