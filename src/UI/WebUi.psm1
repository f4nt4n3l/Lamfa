# Local web UI over the JSON facade.
# Guardrails: binds 127.0.0.1 ONLY, requires a random per-session token on
# every request, serves read + safe-sync operations; state-changing flows with
# typed confirmations stay in the terminal by design.
Set-StrictMode -Version 3.0
Import-Module -Name (Join-Path $PSScriptRoot '../Core/ApiFacade.psm1') -DisableNameChecking
Import-Module -Name (Join-Path $PSScriptRoot 'ConsoleRenderer.psm1') -DisableNameChecking

$script:DashboardHtml = @'
<!DOCTYPE html><html><head><meta charset="utf-8"><title>Lamfa</title>
<style>
body{font-family:Segoe UI,sans-serif;margin:2rem;background:#111;color:#ddd}
h1{color:#4fc3f7}.card{background:#1c1c1c;border:1px solid #333;border-radius:8px;padding:1rem;margin:.7rem 0}
button{background:#263238;color:#eee;border:1px solid #4fc3f7;border-radius:5px;padding:.4rem .9rem;margin:.2rem;cursor:pointer}
button:hover{background:#37474f}.ok{color:#81c784}.warn{color:#ffb74d}.bad{color:#e57373}
pre{background:#0d0d0d;padding:.8rem;border-radius:6px;overflow:auto;max-height:45vh}
table{border-collapse:collapse}td,th{padding:.2rem .8rem;text-align:left}
</style></head><body>
<h1>Lamfa</h1>
<div class="card"><b>Repositories</b><div id="repos">loading...</div></div>
<div class="card"><b>Status</b> <span id="branch"></span>
  <div>
    <button onclick="run('fetch')">Fetch</button>
    <button onclick="run('pull')">Pull (safe)</button>
    <button onclick="load('diff','out')">Diff</button>
    <button onclick="load('history','out')">History</button>
    <button onclick="load('pr.view','out')">Pull request</button>
  </div>
  <div id="status">loading...</div></div>
<div class="card"><pre id="out">Commits, pushes, and anything destructive stay in the terminal - by design (typed confirmations).</pre></div>
<script>
const token=new URLSearchParams(location.search).get('token');
async function api(op,params){const r=await fetch('/api',{method:'POST',headers:{'X-Lamfa-Token':token,'Content-Type':'application/json'},body:JSON.stringify({operation:op,parameters:params||{}})});return r.json()}
function esc(s){return String(s??'').replace(/[&<>]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;'}[c]))}
async function refresh(){
  const repos=await api('repos.list');
  if(repos.ok){document.getElementById('repos').innerHTML=repos.result.repositories.map(r=>`<button onclick="activate('${r.id}')">${esc(r.name)}</button>`).join(' ')}
  const s=await api('status');
  if(!s.ok){document.getElementById('status').innerHTML=`<span class="warn">${esc(s.error)}</span>`;return}
  const st=s.result;
  document.getElementById('branch').textContent=`${st.repository} @ ${st.branch} (ahead ${st.ahead??'-'} / behind ${st.behind??'-'})`;
  document.getElementById('status').innerHTML=st.clean?'<span class="ok">Working tree clean</span>'
    :'<table>'+st.entries.map(e=>`<tr><td>${esc(e.kind)}</td><td>${esc(e.path)}</td></tr>`).join('')+'</table>';
}
async function activate(id){await api('repos.activate',{id});refresh()}
async function run(op){const r=await api(op);document.getElementById('out').textContent=JSON.stringify(r,null,2);refresh()}
async function load(op,target){const r=await api(op);document.getElementById(target).textContent=r.ok?(r.result.text??JSON.stringify(r.result,null,2)):r.error}
refresh();setInterval(refresh,20000);
</script></body></html>
'@

function Lamfa-StartWebUi {
    <#
    .SYNOPSIS
        Serves the local dashboard on 127.0.0.1 with a per-session token
       . Blocks until MaxRequests are served (0 = until Ctrl+C).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][ValidateRange(1024, 65535)][int]$Port = 47613,
        [Parameter()][int]$MaxRequests = 0,
        [Parameter()][string]$ConfigPath = (Lamfa-GetConfigPath),
        [Parameter()][switch]$NoBrowser,
        [Parameter()][AllowEmptyString()][string]$Token = ''
    )
    if (-not $Token) { $Token = [guid]::NewGuid().ToString('N') }
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://127.0.0.1:$Port/")
    $listener.Start()
    $url = "http://127.0.0.1:$Port/?token=$Token"
    Lamfa-WriteMessage -Level Success -Text "Lamfa web UI: $url"
    Lamfa-WriteMessage -Level Info -Text 'Local-only, token-protected. Ctrl+C stops the server.'
    if (-not $NoBrowser) { Start-Process $url }

    $served = 0
    try {
        while ($listener.IsListening) {
            $context = $listener.GetContext()
            $served++
            $request = $context.Request
            $response = $context.Response
            try {
                $providedToken = $request.Headers['X-Lamfa-Token']
                if (-not $providedToken) { $providedToken = $request.QueryString['token'] }
                if ($providedToken -ne $Token) {
                    $response.StatusCode = 401
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes('{"ok":false,"error":"invalid or missing token"}')
                } elseif ($request.HttpMethod -eq 'POST' -and $request.Url.AbsolutePath -eq '/api') {
                    $body = [System.IO.StreamReader]::new($request.InputStream).ReadToEnd()
                    $json = Lamfa-Api -Request $body -ConfigPath $ConfigPath
                    $response.ContentType = 'application/json'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
                } else {
                    $response.ContentType = 'text/html; charset=utf-8'
                    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:DashboardHtml)
                }
                # Explicit length lets the client finish reading before the
                # listener shuts down - without it the last response can be
                # cut off as a connection reset.
                $response.ContentLength64 = $bytes.Length
                $response.OutputStream.Write($bytes, 0, $bytes.Length)
            } finally {
                $response.Close()
            }
            if ($MaxRequests -gt 0 -and $served -ge $MaxRequests) { break }
        }
    } finally {
        $listener.Stop()
        $listener.Close()
    }
}

Export-ModuleMember -Function Lamfa-StartWebUi
