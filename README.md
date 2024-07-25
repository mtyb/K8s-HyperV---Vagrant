# K8s cluster with Vagrant and Hyper-V

**What's done:**

- creates Hyper-V External switch (if not exists)
- creates 3 Vagrant VMs (by default 1 ControlPlane and two Worker Nodes)
- sets static IPs for all VMs
- installs K8s using `KUBEAMD`
- sets IP Forwarding on all nodes
- installs Kubelet and Kubectl (ControlPlane only)
- joins Worker Nodes to Cluster

# SetLab.ps1 overview

Below PowerShell script is designed to manage the creation and destruction of a virtualized Kubernetes cluster using Vagrant and Hyper-V. Below is a detailed explanation of each part of the script:

**Parameters**

```
param (
[int]$controlPlaneCount = 1,
[int]$workerCount = 2,
[string]$mode = 'create'
)
```

- `$controlPlaneCount`: Number of control plane nodes to create (default: 1).
- `$workerCount`: Number of worker nodes to create (default: 2).
- `$mode`: Mode of operation, either 'create' to set up the cluster or 'destroy' to tear it down (default: 'create').

**Create Hyper-V External Switch**

```
$externalSwitch=(Get-VMSwitch | Where-Object SwitchType -eq External).Name
if ($null -eq $externalSwitch)
{
    $newSwitchName="ExternalSwitch"
    New-VMSwitch -name $newSwitchName -NetAdapterName Ethernet -AllowManagementOS $true
    $env:ExtSwitchName=$newSwitchName
}
else
{
$externalSwitch=(Get-VMSwitch | Where-Object SwitchType -eq External) | Select-Object -ExpandProperty Name
    $env:ExtSwitchName=$externalSwitch
}
```

- Checks if an external Hyper-V switch exists. If not, it creates one named "ExternalSwitch".
- Sets an environment variable `$env:ExtSwitchName` with the switch name.

**Network Configuration**

```
$networkName=(Get-VMSwitch | Where-Object SwitchType -eq External).Name
$netAddress=(Get-NetIPAddress -AddressFamily IPv4 | Where InterfaceAlias -eq "vEthernet ($networkName)").IPAddress
$splittedNet=$netAddress.Split('.')
$netPrefix=$splittedNet[0] + '.' + $splittedNet[1] + '.' + $splittedNet[2] + '.'
```

- Retrieves the name of the external switch and the corresponding IP address.
- Extracts the network prefix to configure IP addresses for VMs.

**VM Specifications and Counts**

```
$env:controlPlaneName="k8s-controlplane"
$env:workerName="k8s-node"
$env:cpuCount="2"
$env:memorySize="4096"
$env:controlPlaneCount=$controlPlaneCount
$env:workerCount=$workerCount
$env:linuxBox="gusztavvargadr/ubuntu-server-2404-lts"
```

- Sets environment variables for VM specifications (names, CPU, memory, counts, and the Vagrant box image).

**Script Paths**

```
$env:initiateControlplane="../scripts/initiate_controlplane.sh"
$env:initiateWorker="../scripts/initiate_worker.sh"
```

- Sets environment variables for the paths to the scripts used to initialize the control plane and worker nodes.

**IP Address Configuration**

```
$env:controlPlaneIPs="$netPrefix" + '23'
$env:workerIPs="$netPrefix" + '24'
```

- Assigns static IP addresses to the control plane and worker nodes.

**Create Mode: Run Vagrant**

```
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
    Rename-Item -Path "./scripts/initiate_worker_copy.sh" -NewName "initiate_worker.sh"
    Remove-Item "./logs.txt" -Force -ErrorAction SilentlyContinue

    $vms=Get-VM | Where-Object {($_.Name -match $env:controlPlaneName) -or ($_.Name -match $env:workerName)} | Select-Object -ExpandProperty Name
    foreach($vm in $vms)
    {
        Write-Host "Creating snapshot for $vm..."
        Checkpoint-VM -Name $vm -SnapshotName FreshInstall
        Write-Host "Snapshot created!"
    }

}
```

- If `create` mode is specified, it runs vagrant up for the control plane and worker nodes, waits for configurations, and extracts the kubeadm join command from logs.
- Updates the worker initiation script with the extracted token.
- Creates VM snapshots named "FreshInstall".

**Destroy Mode: Teardown Vagrant**

```
if ($mode -eq 'destroy') {
Stop-Process -Name "ruby" -ErrorAction SilentlyContinue
Set-Location ./workerNodes
vagrant destroy --force
Set-Location ..
Set-Location ./controlPlane
vagrant destroy --force
Set-Location ..
}
```

- If `destroy` mode is specified, it stops any running Ruby processes and forcefully destroys the Vagrant VMs for both the control plane and worker nodes.

**Summary**

This script automates the setup and teardown of a Kubernetes cluster using Hyper-V and Vagrant. It dynamically configures network settings, initializes control plane and worker nodes, and handles token-based worker node joining to the cluster. It also provides functionality to destroy the cluster and clean up resources when no longer needed.
