$port = 8000
$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$port/")
$listener.Start()
Write-Host "Server started at http://localhost:$port/"
try {
    while ($listener.IsListening) {
        $context = $listener.GetContext()
        $request = $context.Request
        $response = $context.Response

        # Get local path
        $urlPath = $request.Url.LocalPath
        if ($urlPath -eq "/") { $urlPath = "/index.html" }
        $localPath = Join-Path "c:\Development\Mixingflavors\build\web" $urlPath.TrimStart('/')

        if (Test-Path $localPath -PathType Leaf) {
            # Set headers for Godot 4 Web exports
            $response.Headers.Add("Cross-Origin-Opener-Policy", "same-origin")
            $response.Headers.Add("Cross-Origin-Embedder-Policy", "require-corp")
            $response.Headers.Add("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
            $response.Headers.Add("Pragma", "no-cache")
            $response.Headers.Add("Expires", "0")
            
            # Content Type
            $ext = [System.IO.Path]::GetExtension($localPath)
            switch ($ext) {
                ".html" { $response.ContentType = "text/html" }
                ".js"   { $response.ContentType = "application/javascript" }
                ".wasm" { $response.ContentType = "application/wasm" }
                ".pck"  { $response.ContentType = "application/octet-stream" }
                ".png"  { $response.ContentType = "image/png" }
                default { $response.ContentType = "application/octet-stream" }
            }

            $bytes = [System.IO.File]::ReadAllBytes($localPath)
            $response.ContentLength64 = $bytes.Length
            $response.OutputStream.Write($bytes, 0, $bytes.Length)
        } else {
            $response.StatusCode = 404
        }
        $response.Close()
    }
} finally {
    $listener.Stop()
}
