This folder contains a collection of templates, PowerShell modules and scripts that helps you manage Azure DevOps Environments and respective Kubernetes Resources.

Please see detailed explanation and guides in these blog posts:

[Continuous Delivery to AKS With Azure DevOps Environments - Part 1](https://kristhecodingunicorn.com/post/k8s_ado_envs-1)
[Continuous Delivery to AKS With Azure DevOps Environments - Part 2](https://kristhecodingunicorn.com/post/k8s_ado_envs-2)
[Re-Using Azure DevOps Environment Efficiently Across Multiple Pipelines](https://kristhecodingunicorn.com/techtips/ado_env_as_var)
[How to Fix ServiceAccount Error in Azure DevOps Environments for Kubernetes Clusters V.1.24 and Newer](https://kristhecodingunicorn.com/techtips/ado_sa_error)

```New-ADO-K8s-Resources.ps1```

This script automatically creates either an AKS Resource or a Generic Kubernetes Provider Resource in an existing Azure DevOps Environment. If an Environment doesn't exist from before, the script may create it if a respective parameter is provided upon execution.
If Generic Kubernetes Provider Resource is created, a Kubernetes Service Account with respective Secret and RoleBinding will be generated automatically in the namespace in the Kubernetes cluster where the Resource will be deployed.

In order to run the script following pre-requisites must be in place: 

- Azure DevOps PAT with permissions that allow the script to create and manage Azure DevOps Environments with Resources and Service Connections.

- PowerShell 7+, Azure CLI and kubectl must be installed. Don't forget to set correct Azure subscription and Kubernetes Context to the correct cluster prior to script execution ;-)

You can execute the script like this:

1. To create an Azure DevOps Environment Generic Kubernetes Provider Resource: 

```./New-ADO-K8s-Resource.ps1 -AccessToken "<azure_devops_pat>" -AzureDevOpsUrl "https://dev.azure.com/<organization_name>/<project_name>" -EnvironmentName "<azure_devops_environment_name>" -KubernetesClusterName "<kubernetes_cluster_name>" -KubernetesResourceNamespace "<application_namespace_in_kubernetes_cluster>" -KubernetesClusterUrl "https://<kubernetes_cluster_server_url>" -AcceptUntrustedCertificates $true```

2. To create an Azure DevOps Environment AKS Resource: 

```./New-ADO-K8s-Resource.ps1 -AccessToken "<azure_devops_pat>" -AzureDevOpsUrl "https://dev.azure.com/<organization_name>/<project_name>" -EnvironmentName "<azure_devops_environment_name>" -KubernetesClusterName "<kubernetes_cluster_name>" -KubernetesResourceNamespace "<application_namespace_in_kubernetes_cluster>" -SubscriptionId "<azure_subscription_id_where_aks_cluster_is_provisioned>"```

---

```Move-AKS-Environments.ps1```

This script automatically moves all AKS Resources between Azure DevOps Environments. If a target Azure DevOps Environment doesn't exist, it will be created. Resources moved to a new AFO Environment can target the same AKS cluster as before or can target a new AKS cluster.

In order to run the script following pre-requisites must be in place: 

- Azure DevOps PAT with permissions that allow the script to create and manage Azure DevOps Environments with Resources and Service Connections.

- PowerShell 7+, Azure CLI and kubectl must be installed. Don't forget to set correct Azure subscription and Kubernetes Context to the correct cluster prior to script execution ;-)

You can execute the script like this:

1. Move resources from Environment1 to Environment2 and target the same AKS cluster: 

```./Move-AKS-Environments.ps1 -AccessToken "azure-devops-pat" -AzureDevOpsUrl "https://azure-devops-url/org-name/project-name/" -SourceEnvironmentName "Environment1" -TargetEnvironmentName "Environment2" -TargetEnvironmentDescription "New target Azure DevOps Environment"```

2. Move resources from Environment1 to Environment2 and target new AKS cluster "NewAKSCluster": 

```./Move-AKS-Environments.ps1 -AccessToken "azure-devops-pat" -AzureDevOpsUrl "https://azure-devops-url/org-name/project-name/" -SourceEnvironmentName "Environment1" -TargetEnvironmentName "Environment2" -TargetClusterName "NewAKSCluster" -SubscriptionId "aks-cluster-azure-subscription-id"```

---

Both scripts use a PowerShell module that is located in the ```modules``` folder - it contains a collection of functions to manage Azure DevOps Environments and Resources. If you want to use this module outside of the scripts that are mentioned above, you can import it with ```Import-Module "./modules/Manage-Ado-Environment.psm1"```.