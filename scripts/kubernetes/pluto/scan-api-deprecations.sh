#!/bin/bash
reposToScan=("[repository_name") # in case of multiple repos, separate them with whitespace, f.ex. ("repo1" "repo2" "repo3")
      
for repo in "${reposToScan[@]}"; do
    repoDir="$1/$repo"

    printf "\n*********** $repo ************\n"
    printf "\nYAML TEMPLATES:\n"
    ./pluto detect-files -d "$repoDir" -o markdown --ignore-deprecations --ignore-removals # 2 last parameters can be removed if you want script to fail in case deprecations/removals have been detected

    IFS=$'\n'
    helmChartsDir=($(find "$repoDir" -type f -iname "Chart.yaml"))
    printf "\nHELM TEMPLATES:\n"

    if [ -z "$helmChartsDir" ]; then
        echo "No Helm templates found!"
        continue
    fi

    for helmChartDir in "${helmChartsDir[@]}"; do
        printf "\nLocated Helm Chart:$helmChartDir\n"
        helmChartBaseDir="$(dirname "${helmChartDir}")"

        helmValuesFile=$(find "$helmChartBaseDir" -type f -iname "values.yaml")

        # If you're using custom Helm values files, you can comment above line and have more granular filtering of values file with the commented code block below        
        #helmValuesFile=$(find "$helmChartBaseDir" -type f -regextype posix-extended -iregex '.*values-prod.yaml|.*deploy-values.yaml')
        #if [ -z "$helmValuesFile" ]; then 
        #    helmValuesFile=$(find "$helmChartBaseDir" -type f -iname "values.yaml")
        #fi
        
        printf "\nLocated Helm values file:$helmValuesFile -> checking...\n"
        helm template "$helmChartBaseDir" -f "$helmValuesFile" | ./pluto detect - -o markdown --ignore-deprecations --ignore-removals 
    done
    printf "\n*******************************\n"
done
      
echo "Pluto executed scanning successfully!"