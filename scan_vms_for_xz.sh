#!/opt/homebrew/bin/zsh

# Function to check if 'xz' is installed and get its version
check_xz() {
    local subscription=$1
    local vm=$2
    local rg=$3
    local current_date=$4

    # Check if VM is running
    vm_status=$(az vm get-instance-view --name $vm --resource-group $rg --query instanceView.statuses[1] --o tsv)

    if [[ $vm_status != *"running"* ]]; then
        echo "$subscription,$vm,N/A,N/A,machine is stopped" >> vm_scan_${current_date}.csv
        return
    fi

    # Check if 'xz' is installed and get its version
    result=$(az vm run-command invoke -g $rg -n $vm --command-id RunShellScript --scripts "command -v xz && if [ $? -eq 0 ]; then xz --version | head -n 1; else echo 'command not found'; fi" --query 'value[0].message' -o tsv | tr -s '\n')

    # Check if 'xz' is installed
    if [[ $result == *"command not found"* ]]; then
        is_installed="No"
        version="N/A"
    else
        is_installed="Yes"
        version=$(echo $result | awk '{print $4}' | tr -d '[:space:]' | tr -d '\n')
    fi

    # Write to output file
    echo "$subscription,$vm,$is_installed,$version," >> scan_vms_for_xz_${current_date}.csv
}

# Get list of subscriptions
IFS=$'\n' subscriptions=($(az account list --query "[].name" -o tsv))

# Get current date and time
current_date=$(date +"%d.%m.%Y")

# Initialize output file
echo "Subscription,VM Name,Is XZ Installed,XZ Version,Comments" > scan_vms_for_xz_${current_date}.csv

# Loop over all subscriptions
for subscription in "${subscriptions[@]}"
do
    # Set the subscription
    az account set --subscription "$subscription"

    # Get all VMs and their resource groups
    vms=$(az vm list --query "[?storageProfile.osDisk.osType=='Linux'].{Name:name, ResourceGroup:resourceGroup}" -o tsv)

    # Skip if no VMs
    if [ -z "$vms" ]; then
        continue
    fi

    echo "----------------------------------------"
    echo "Subscription: $subscription"
    echo "VMs: $vms"
    echo "----------------------------------------"

    # Loop over all VMs
    while IFS=$'\t' read -r vm rg
    do
        echo "----------------------------------------"
        echo "VM: $vm, Resource Group: $rg"
        echo "----------------------------------------"

        # Call the function in the background
        check_xz "$subscription" "$vm" "$rg" "$current_date" &
    done <<< "$vms"

    # Wait for all background jobs to finish
    wait
done