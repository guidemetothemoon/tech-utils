# Azure Policy definition to whitelist deployment locations

A custom Azure Policy definition to allow deployment of AKS clusters only to whitelisted locations, like for example "northeurope".

Policy Metadata for reference:

``` json
"properties": {
  "displayName": "Create AKS clusters only in North Europe",
  "policyType": "Custom",
  "mode": "All",
  "description": "This policy will enforce creation of AKS clusters only in North Europe location.",
  "metadata": {
    "category": "Kubernetes",
    "version": "1.0.0"
  }
}
```
