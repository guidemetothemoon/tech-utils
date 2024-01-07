<!-- Work in progress... -->
# Bicep Cheatsheet Overview

This cheatsheet contains information about useful functions and best practices that have proven to work well for me throughout the time I've worked with Bicep in different projects and as part of my community involvement. Many of these practices are also cross-checked with official documentation, community experiences and other trustworthy resources.

*Disclaimer: this is not a single source of truth type of document and it doesn't force you to do things only in this way. In some use cases some best practices may be different from what's stated here, and that's OK as long as there's a reason behind a different approach. This document is meant to get a quicker overview of useful practices, tips and tricks for provisioning and managing infrastructure provisioning with Bicep.*

## Best practices

### Naming convention

- Use camelCase for names, for example ```param clusterName string = 'aks-cluster-dev'```

### File && Folder structure

### Other

- Provide meaningful description for parameters, at least where the parameter name is not fully descriptive and may create room for assumption or confusion. Meaningful ≠ parameter name only. For example:

``` bicep
@description('The size of the Virtual Machines that will be used by the AKS user node pool.')
param nodePoolSize string = 'Standard_B2s'
```

- Put parameter declarations on top of the template file.
- Reference variable directly by its name.

## Useful functions
