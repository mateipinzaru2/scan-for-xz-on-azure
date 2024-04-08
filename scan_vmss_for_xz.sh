#!/opt/homebrew/bin/zsh

# Script is WIP, currently not working as expected. The "az vmss run-command create" command is getting stuck and not returning any output.

# Function to check if 'xz' is installed and get its version
check_xz() {
    local subscription=$1
    local vmss=$2
    local rg=$3
    local current_date=$4

    # Check if VMSS is running
    vmss_status=$(az vmss list-instances --name $vmss --resource-group $rg --query "[?provisioningState=='Succeeded']" -o tsv)

    if [[ -z $vmss_status ]]; then
        echo "$subscription,$vmss,N/A,N/A,machine is stopped" >> vmss_scan_${current_date}.csv
        return
    fi

    # Check if 'xz' is installed and get its version
    result=$(az vmss run-command create -g $rg -n $vmss --command-id RunShellScript --instance-id @- --script "command -v xz && if [ $? -eq 0 ]; then xz --version | head -n 1; else echo 'command not found'; fi" --query 'value[0].message' -o tsv | tr -s '\n')

    # Check if 'xz' is installed
    if [[ $result == *"command not found"* ]]; then
        is_installed="No"
        version="N/A"
    else
        is_installed="Yes"
        version=$(echo $result | awk '{print $4}' | tr -d '[:space:]' | tr -d '\n')
    fi

    # Write to output file
    echo "$subscription,$vmss,$is_installed,$version," >> vmss_scan_${current_date}.csv
}

# Get list of subscriptions
IFS=$'\n' subscriptions=($(az account list --query "[].name" -o tsv))

# Get current date and time
current_date=$(date +"%Y%m%d_%H%M%S")

# Initialize output file
echo "Subscription,VMSS Name,Is XZ Installed,XZ Version,Comments" > vmss_scan_${current_date}.csv

# Loop over all subscriptions
for subscription in "${subscriptions[@]}"
do
    # Set the subscription
    az account set --subscription "$subscription"

    # Get all VMSS and their resource groups
    vmsses=$(az vmss list --query "[?virtualMachineProfile.storageProfile.osDisk.osType=='Linux'].{Name:name, ResourceGroup:resourceGroup}" -o tsv)

    # Skip if no VMSS
    if [ -z "$vmsses" ]; then
        continue
    fi

    echo "----------------------------------------"
    echo "Subscription: $subscription"
    echo "VMSS: $vmsses"
    echo "----------------------------------------"

    # Loop over all VMSS
    while IFS=$'\t' read -r vmss rg
    do
        echo "----------------------------------------"
        echo "VMSS: $vmss, Resource Group: $rg"
        echo "----------------------------------------"

        # Call the function in the background
        check_xz "$subscription" "$vmss" "$rg" "$current_date" &
    done <<< "$vmsses"

    # Wait for all background jobs to finish
    wait
done