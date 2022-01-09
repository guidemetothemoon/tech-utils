# This script will include missing PodDisruptionBudget resource (defined in pdb.yaml) to existing Helm release of your application.
# Script can be customized to apply any other resource - you will then either need to apply your own yaml-file containing the resource definition or edit referenced pdb.yaml to define
# your resource instead.

# OBS! Ensure that you're connected to the correct Kubernetes cluster BEFORE executing the script
# OBS! Replace 'mytestapp' with your deployment name

# This filter can be adjusted to filter only the deployments you want to apply PodDisruptionBudget to. Current filter is for the deployments of mytestapp only
$deployments=((kubectl get deployments.apps -A -o json | ConvertFrom-Json).items) | Where-Object {$_.metadata.name -match 'mytestapp'};

foreach($deploy in $deployments){

  # 1. For each deployment, get raw content of yaml file and deployment values to update the yaml with
  $pdb_yaml = Get-Content $PSScriptRoot/pdb.yaml -Raw
  $deploy_name = $deploy.metadata.name
  $deploy_ns = $deploy.metadata.namespace

  $labels = $deploy.spec.selector.matchLabels 
  $label_props = $labels | get-member -MemberType NoteProperty

  $formatted_labels = ""

  # 2. There may be multiple selectorLabels so we need to ensure that those are formatted according to the YAML formatting laws

  foreach($labelName in $label_props.Name)
  {
    # Due to YAML strictness on formatting we'll use this hack to format multiple selector labels in the allowed way
    $formatted_labels += "      $($labelName): $($labels.$labelName)`n"    
  }

  # 3. Replace placeholders in YAML-file with mytestapp deployment values
  
  $pdb_yaml = $pdb_yaml.Replace('[deployment_name]',$deploy_name).Replace('[deployment_namespace]',$deploy_ns).Replace('[deployment_labels]',$formatted_labels)
  $pdb_yaml | Out-File -FilePath "$PSScriptRoot/pdb-$($deploy_name).yaml" -Encoding utf8

  # 4. Apply updated YAML-file to add PodDisruptionBudget for current deployment
  
  Write-Output "Applying PDB deployment pdb-$($deploy_name).yaml for deployment $deploy_name"
  kubectl apply -f "$PSScriptRoot/pdb-$($deploy_name).yaml"
}