# Kubernetes Debugging Notes

## General information and tips

- If a pod is stuck in **Pending** it means that it can not be scheduled onto a node. Generally this is because there are insufficient resources.
- If a pod is stuck in the **Waiting** state, then it has been scheduled to a worker node, but it can't run on that machine.
- **CrashloopBackOff** means that you have a pod starting, crashing, starting again, and then crashing again.

- To spare some time, I recommend setting an alias for kubectl command so that you don't need to type kubectl every single time you want to run a command. Be aware that alias is active only for current shell session. PowerShell command to set alias: `Set-Alias -Name k -Value kubectl`

**Note: From now on I will be using k instead of kubectl in command examples.**

- To see configuration information about the container(s) and Pod(s) (labels, resource requirements, etc.), as well as status information about the container(s) and Pod(s) (state, readiness, restart count, events, etc.): `k describe pod <pod_name> -n <namespace>`

- To get all information Kubernetes has about a specific Pod: `k describe pod <pod_name> -n <namespace> -o yaml`

- To scale deployment up or down: `k scale --replicas=<replica_count> deploy <deployment_name> -n <namespace>`

- To get all events for current namespace: `k get events -n <namespace>`

- If your container has previously crashed, you can access the previous container's crash log with:
`k logs --previous <pod_name> -n <namespace>`

**Note: I will be using some concrete examples of things that may go wrong when operating Kubernetes clusters, for better illustration of debugging process.**

## WORKLOADS

**1.** We have Clamav (Linux antivirus) deployment where Pods are in CrashLoopBackOff (spoiler: outdated version, upgrade of image needed to resolve the problem): start by checking events with describe, check logs, edit deploy and upgrade version, watch pods;

`k get pods -A` -> get Pods in all namespaces

`k describe pod -n clamav clamav-569fd5bcc6-4bbqn` -> identify Clamav namespace, get details about one of the crashing Pods

`k logs -n clamav  clamav-569fd5bcc6-4bbqn` -> retrieve detailed logs of the Pod

`k edit deploy clamav -n clamav  clamav-569fd5bcc6-4bbqn` -> based on logs identify that image must be upgraded. Edit Clamav deployment to update version of the container image to fix existing deployment (remember to update in source code as well to fix for all the future deployments)

`k get pods -n clamav –watch` -> after deployment has been updated, Kubernetes will spin up new Pods with newer image version to satisfy changed deployment requirements - watch start-up live with -watch param

**2.** Debugging Pending externalIP state for NGINX Ingress Controller LoadBalancer Service (spoiler: we forgot to create Public IP before asking a new Ingress Controller to use it). This may have happened if you, for example, uninstalled existing Ingress Controller and when creating a new one, required it to use an IP of the previous Ingress Controller without explicitly reserving that IP beforehand -> result of this will be external IP in Pending state. Resolution would be either to explicitly reserve a specific Public IP, use Azure Load Balancer's Public IP (if using AKS) or not define any IP upon resource creation - it will then automatically choose any available Public IP

`k svc -n ingress-temp` -> get Ingress Controller Services, locate LoadBalancer Service, verify that ExternalIP is in ```<pending>``` state

`k describe svc nginx-ingress-temp-controller -n ingress-temp` -> check for events that might have been raised during Load Balancer Service creation and execution

`k get events --all-namespaces` -> get events in all namespaces in a Kubernetes cluster, find errors like "Error syncing load balancer: failed to ensure load balancer: findMatchedPIPByLoadBalancerIP: cannot find public IP with IP address ```<ip_address>``` in resource group ```<azure_resource_group>```

`k cluster-info dump > cluster_logs.log` -> get detailed information about the overall health of your cluster and save to a file in your current directory to get even more information

**3.** TLS errors in your application due to failed renewal of Let's Encrypt certificate by ```cert-manager```: related to TLS cert provisioning, first, check logs in ```cert-manager``` -> you can see errors related to amount of duplicate certs provisioned too many times
Solution: wait until it's OK to provision again (normally, a week) or re-use already provisioned and not expired certificate

`k logs -n <app_namespace> <pod_name>` -> get logs to see the state and errors of application

If you see TLS errors -> might be related to TLS certificate provisioning, check logs in ```cert-manager```:

`k get pods -n cert-manager`

`k logs <cert_manager_pod_name> -n cert-manager` -> You may see errors like: ```"failed to create Order resource due to bad request, marking Order as failed" "error"="429 urn:ietf:params:acme:error:rateLimited: Error creating new order :: too many certificates (5) already issued for this exact set of domains in the last 168 hours: *.dev.mytestapp.com: see https://letsencrypt.org/docs/rate-limits/" "resource_kind"="Order" "resource_name"="wildcard-dev-mytestapp-com-314354315594-19847372193" "resource_namespace"="cert-manager"```

A certificate is considered a renewal (or a duplicate) of an earlier certificate if it contains the exact same set of hostnames, ignoring capitalization and ordering of hostnames. Duplicate Certificate limit of 5 per week for production API. So in some cases, like when using a wildcard certificate, you will need to be careful about how often you provision it and in what scenarios so that you don't end up in violating existing limitations.

**4.** Issues during runtinme of a Windows application: start by logging into the pod on a Windows node: check network connectivity, get processes, event logs, check application configuration

`k exec -n <app_namespace> <pod_name> -it -- powershell` -> log into the pod and start PowerShell

`Invoke-WebRequest -Uri http://localhost:81/mytestappsvc/healtz` -> call app's health endpoint

`Invoke-WebRequest -Uri http://www.google.com -UseBasicParsing` -> verify external network connectivity

`Get-Service <service_name>`, `Start-Service <service_name>`, `Stop-Service <service_name>`, `Restart-Service <service_name>` -> get information about available services, start/stop/restart a service

`Get-IISAppPool`, `Get-IISSite` -> get information about available application pools and sites hosted in IIS

`Get-Process -Name <process_name>` -> get information about running processes

`Get-EventLog -List` -> get entries logged to the Event Log

`Get-EventLog -LogName SI.Biz.System -Newest 10 | Format-List` -> get 10 newest entries added to Event Log

`Get-EventLog -LogName SI.Biz.System -Newest 10 -EntryType Error | Format-Table -wrap` -> get 10 newest errors added to Event Log

`cat .\mytestapp.config` -> Print content of the application configuration file

`vim .\mytestapp.config` -> View/Edit application configuration file with Vim

`exit` -> Once debugging is done, log off the Pod

**5.** Log to a Linux Pod (using Redis Pod as an example here) -> check network connectivity

`k exec -n redis redis-1 -it -- bash` -> log into the pod and start Bash

`curl -I http://www.google.com` -> verify external network connectivity

## NODES

**1. Overall about nodes:**

`k get nodes -o wide` -> (See state Ready/Not Ready)

`k describe node akswinpol000000` -> (Terminated Pods, resource exhaustion, disk/memory/kubelet pressure)

`k get node akswinpol000000 -o yaml` -> get all information Kubernetes has about this Node

**2.** Log into Linux node: check network, check installed packages. Start a privileged container on your node and connect to it over SSH. More information for AKS can be found here: [Create the SSH connection to a Linux node](https://docs.microsoft.com/en-us/azure/aks/ssh#create-the-ssh-connection-to-a-linux-node)

`kubectl debug node/aks-nodepool1-18956626-vmss000000 -it --image=mcr.microsoft.com/aks/fundamental/base-ubuntu:v0.0.11` -> start privileged debugging Linux container

`curl -I http://www.google.com` -> verify external network connectivity from Node

`apt list –installed` -> get installed apps

`apt list –upgradable` -> get any pending upgrades on apps

Check logs:

**/var/log/kubelet.log** - Kubelet, responsible for running containers on the Node

**/var/log/kube-proxy.log** - Kube Proxy, responsible for Service load balancing

**3.** Log into Windows Node: for that you will need to create a jump server first. More information for AKS can be found here: [Connect with RDP to Azure Kubernetes Service (AKS) cluster Windows Server nodes for maintenance or troubleshooting](https://docs.microsoft.com/en-us/azure/aks/rdp)

Once jump server is created, start RDP and log to the jump server. Once logged into the jump server, again open RDP (inside the jump server), and enter the IP address of the node you want to connect to.

`curl -I http://www.google.com` -> verify external network connectivity from Node

`powershell`, `taskmgr`, `notepad`, `cmd` -> Start PowerShell, Task Manager, Notepad, Command Shell++.Can even install browser and get it opened as part of the session.

**4.** Check top nodes for performance to see if some nodes are experiencing resource exhaustion. Drain a node if maintenance must be done on the node.

You can use kubectl drain to safely evict all of your pods from a node before you perform maintenance on the node (e.g. kernel upgrade, hardware maintenance, etc.). Safe evictions allow the pod's containers to gracefully terminate and will respect the PodDisruptionBudgets you have specified. When kubectl drain returns successfully, that indicates that all of the pods (except the ones excluded as described in the previous paragraph) have been safely evicted (respecting the desired graceful termination period, and respecting the PodDisruptionBudget you have defined). It is then safe to bring down the node by powering down its physical machine or, if running on a cloud platform, deleting its virtual machine.

`k get pods -n <application_namespace>` -> get pods that your application is running on

`k get pdb -n <application_namespace>` -> check defined PodDisruptionBudget for allowed disruption on workload

`k top nodes --use-protocol-buffers` -> get nodes using most CPU and memory

`k get pods -n <application_namespace> -o wide --watch` - get all pods in application's namespace with additional information like Pod IP, watch them live

`k drain --delete-emptydir-data --force --ignore-daemonsets aks-nodepool1-20800050-vmss000001` -> drain will take node offline so that you can perform maintenance on it

... let's say we've done some maintenance on the node, now we can make it schedulable again with uncordon:

`k uncordon aks-nodepool1-20800050-vmss000001` -> now, workloads can be scheduled again on a node

## Debugging and monitoring possibilities in AZURE PORTAL

Diagnostic and health check in Azure Portal -> go to Azure Kubernetes Service page and choose your cluster

-> check these tabs on the right-hand side:

**a.** Resource health tab

**b.** Diagnose and solve problems

**c.** Insights (Azure Monitor) -> Cluster, Nodes, Controllers, Containers + Live logs & events

**d.** Metrics

**e.** Workbooks

**f.** Logs

**g.** Workloads

**h.** Security tab!

Additional information about monitoring in AKS can be found here: [Monitoring Azure Kubernetes Service (AKS) with Azure Monitor](https://docs.microsoft.com/en-us/azure/aks/monitor-aks)
