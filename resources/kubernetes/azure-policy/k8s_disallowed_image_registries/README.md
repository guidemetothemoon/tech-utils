A custom Azure Policy definition to disallow Kubernetes workloads that are referencing disallowed/blacklisted image registries, like for example "k8s.gcr.io".

Policy Metadata for reference:

```
"properties": {
  "displayName": "Kubernetes clusters should not allow legacy image registries",
  "policyType": "Custom",
  "mode": "Microsoft.Kubernetes.Data",
  "description": "Do not allow containers to depend upon deprecated image registries like gcr.k8s.io. Read for more information: https://kubernetes.io/blog/2023/03/10/image-registry-redirect/",
  "metadata": {
    "category": "Kubernetes",
    "version": "1.0.0"
  }
}
```