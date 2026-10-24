$required = @(
    @{ Name = 'git';     Cmd = 'git';     Ver = { git --version };                                  Install = 'winget install Git.Git' },
    @{ Name = 'docker';  Cmd = 'docker';  Ver = { docker version --format '{{.Client.Version}}' };  Install = 'Docker Desktop' },
    @{ Name = 'kubectl'; Cmd = 'kubectl'; Ver = { kubectl version --client 2>&1 | Select-Object -First 1 }; Install = 'ships with Docker Desktop, or: winget install Kubernetes.kubectl' },
    @{ Name = 'kind';    Cmd = 'kind';    Ver = { kind version };                                   Install = 'winget install Kubernetes.kind' },
    @{ Name = 'helm';    Cmd = 'helm';    Ver = { helm version --short };                           Install = 'winget install Helm.Helm' },
    @{ Name = 'python';  Cmd = 'py';      Ver = { py -3.12 --version };                             Install = 'Python 3.12 from python.org (you already have it)' }
)

$missing = @()
foreach ($t in $required) {
    if (Get-Command $t.Cmd -ErrorAction SilentlyContinue) {
        $v = try { (& $t.Ver 2>&1 | Select-Object -First 1) } catch { 'installed' }
        '{0,-9} OK       {1}' -f $t.Name, $v
    } else {
        '{0,-9} MISSING  install: {1}' -f $t.Name, $t.Install
        $missing += $t.Name
    }
}

if (Get-Command docker -ErrorAction SilentlyContinue) {
    $sv = docker version --format '{{.Server.Version}}' 2>$null
    if ($sv) {
        '{0,-9} OK       engine {1}' -f 'engine', $sv
        $mem = docker info --format '{{.MemTotal}}' 2>$null
        if ($mem) {
            $gb = [math]::Round([double]$mem / 1GB, 1)
            if ($gb -lt 6) { '{0,-9} LOW      Docker has {1} GB; 6 GB or more is comfortable for kind + monitoring' -f 'memory', $gb }
            else { '{0,-9} OK       Docker has {1} GB' -f 'memory', $gb }
        }
    } else {
        '{0,-9} DOWN     Docker engine is not responding' -f 'engine'
        $missing += 'docker-engine'
    }
}

if ($missing.Count -gt 0) {
    Write-Host ("`nMissing or not ready: " + ($missing -join ', ')) -ForegroundColor Yellow
    Write-Host "After installing, close and reopen PowerShell so PATH updates, then run this block again." -ForegroundColor Yellow
    exit 1
}
Write-Host "`nAll required tools are present." -ForegroundColor Green
exit 0