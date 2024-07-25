param (
  [int]$controlPlaneCount = 1,
  [int]$workerCount = 2,
  [string]$mode = 'create'
)

### create Hyper-V External Switch - if not exists ###
$externalSwitch=(Get-VMSwitch | Where-Object SwitchType -eq External).Name
if ($null -eq $externalSwitch) 
{ $newSwitchName="ExternalSwitch"
  New-VMSwitch -name $newSwitchName -NetAdapterName Ethernet -AllowManagementOS $true
  $env:ExtSwitchName=$newSwitchName }
else 
{ $externalSwitch=(Get-VMSwitch | Where-Object SwitchType -eq External) | Select-Object -ExpandProperty Name
  $env:ExtSwitchName=$externalSwitch }

$networkName=(Get-VMSwitch | Where-Object SwitchType -eq External).Name
$netAddress=(Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -eq "vEthernet ($networkName)").IPAddress
$splittedNet=$netAddress.Split('.')
$netPrefix=$splittedNet[0] + '.' + $splittedNet[1] + '.' + $splittedNet[2] + '.'

### set variables - VM spec ###
$env:controlPlaneName="k8s-controlplane"
$env:workerName="k8s-node"
$env:cpuCount="2"
$env:memorySize="4096"

### set variables - VM count and box name ###
$env:controlPlaneCount=$controlPlaneCount
$env:workerCount=$workerCount
$env:linuxBox="gusztavvargadr/ubuntu-server-2404-lts"

### set variables - scripts paths ###
$env:initiateControlplane="../scripts/initiate_controlplane.sh"
$env:initiateWorker="../scripts/initiate_worker.sh"

### set variables for IPs ###
$env:controlPlaneIPs="$netPrefix" + '23'
$env:workerIPs="$netPrefix" + '24'

### run Vagrant ###
if ($mode -eq 'create') {
  Start-Transcript -Path "./logs.txt" -NoClobber
  Set-Location ./controlPlane
  vagrant up | Out-Host
  Stop-Transcript
  Write-Host "Waiting for VM configuration..."
  Start-Sleep -s 90
  Write-Host "Done!"
  Set-Location ..
  $logs=Get-Content "./logs.txt"
  $kubeadm=($logs | Select-String -Pattern "kubeadm join").ToString()
  $token=$kubeadm.Replace('controlPlane1: ', '').Replace(' \', "")
  $initiateWorkerScript="./scripts/initiate_worker.sh"
  Copy-Item "./scripts/initiate_worker.sh" "./scripts/initiate_worker_copy.sh"
  (Get-Content $initiateWorkerScript).Replace('[TOKEN]', $token) | Set-Content $initiateWorkerScript
  Set-Location ./workerNodes
  vagrant up | Out-Host
  Write-Host "Waiting for VM configuration..."
  Start-Sleep -s 90
  Write-Host "Done!"
  Set-Location ..
  Remove-Item "./scripts/initiate_worker.sh"
  Rename-Item -Path  "./scripts/initiate_worker_copy.sh" -NewName "initiate_worker.sh"
  Remove-Item "./logs.txt" -Force -ErrorAction SilentlyContinue

  ### create VMs snapshots ###
  $vms=Get-VM | Where-Object {($_.Name -match $env:controlPlaneName) -or ($_.Name -match $env:workerName)} | Select-Object -ExpandProperty Name
  foreach($vm in $vms)
  {
      Write-Host "Creating snapshot for $vm..."
      Checkpoint-VM -Name $vm -SnapshotName FreshInstall
      Write-Host "Snapshot created!"
  }
}

if ($mode -eq 'destroy') {
  Stop-Process -Name "ruby" -ErrorAction SilentlyContinue
  Set-Location ./workerNodes
  vagrant destroy --force
  Set-Location ..
  Set-Location ./controlPlane
  vagrant destroy --force
  Set-Location ..
}