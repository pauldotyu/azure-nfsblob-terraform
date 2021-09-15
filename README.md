# azure-nfsblob-terraform

Provision an environment to demonstrate how to mount Azure Blob containers using NFSv3 and secure using Azure Private Endpoints with Network Security Groups

> This repo assumes you are working within a native Linux OS or WSL2

## Prerequisites:

- Have Terraform locally installed
- Optionally, have a Terraform Cloud account
    - If you do not want to use Terraform Cloud for remote state you can simply remove or comment out all the contents in [backend.tf](./backend.tf)
    - If you do have a Terraform Cloud account:
      - Make sure to update [backend.tf](./backend.tf) to point to your `organization` and `workspace`
      - Make sure your workspace settings is set to **Local** as the **Execution Mode** (we'll only use this for remote state)
      - Login into the account using the `terraform login` command
- Have Azure CLI locally installed
- Log in to your Azure subscription using the `az login` command
- This deployment leverages your SSH public key on your local machine for publicly accessible VMs, so make sure you have run `ssh-keygen` locally to generate your key pair

## The following resources will be provisioned:

- Virtual network with 2 subnets
    - public - where VMs with public IPs will be placed
    - private - where private endpoint NIC will be placed
- Network Security Group linked to public subnet
    - Allow SSH from my public IP
- Network Security Group linked to private subnet
    - Allow any Tcp traffic from specified endpoints
    - Deny all other traffic to private subnet
- Storage Account with a default deny network rule with the following exceptions:
    - My public IP
    - public subnet
- Blob storage container named "myblobs"
- Two Linux VMs in public subnet
- Private endpoint for blob storage linked to private subnet
- Private DNS zone for blob storage
    - Link to virtual network for name resolution

## Deploy resources using Terraform and execute NFSv3 mount:

- Run `terraform apply` and confirm the deployment
- The public IP of the virtual machines is listed in the output, you can `ssh` using that
- To mount the blob container using NFSv3, follow these general steps

    ```sh
    # upgrade and install
    sudo apt update
    sudo apt install nfs-common -y

    # create a new mount point
    sudo mkdir /mnt/test

    # mount the drive make sure your storage account name is updated in the command below
    sudo mount -o sec=sys,vers=3,nolock,proto=tcp sanfsblob901.blob.core.windows.net:/sanfsblob901/myblobs  /mnt/test

    # assume ownership
    sudo chown -R $USER /mnt/test

    # test the mount
    touch /mnt/test/myfile.txt
    ls /mnt/test
    ```

## Securing access to NFSv3 enabled blob storage using Azure Private Endpoint and Network Security Groups:

If you are looking to have finer grained control on which resources can access your blob storage account, you can leverage private endpoints with NSG which is currently in public preview (as of 9/2/21):

> https://azure.microsoft.com/en-us/updates/public-preview-of-private-link-network-security-group-support/

> https://azure.microsoft.com/en-us/updates/public-preview-of-private-link-udr-support/

To enable the preview feature, follow these steps:

- Register the `Microsoft.Network/AllowPrivateEndpointNSG` feature using the following command:

    ```sh
    # this takes about 15 minsutes
    az feature register --name AllowPrivateEndpointNSG --namespace Microsoft.Network
    # view the status and wait for Registered
    az feature show --name AllowPrivateEndpointNSG --namespace Microsoft.Network
    ```

Here is a high-level overview of the steps taken to secure the blob container when using NFSv3.

> Note: this configuration is included in the Terraform configuration files

- Create a new private subnet
- Create a private endpoint for the storage account and link it to the new private subnet
- Creation of a private endpoint in the Azure Portal will also create a Azure Private DNS zone, make sure this zone is linked to your virtual network
- Set the `disable-private-endpoint-network-policies` flag to false using the following command (NOTE: this is already configured for the `private` subnet in the Terraform configuration file):
    ```sh
    # this makes the NSGs work
    az network vnet subnet update --disable-private-endpoint-network-policies false --name private --resource-group rg-nfsblob --vnet-name vn-nfsblob
    ```
- Create a new network security group and associate it with the new private subnet
- Add rules as needed:
    - Allow traffic from your "approved sources" (network range, list of IPs, single IP)
    - Deny all other traffic to the new private subnet IP range

## Validation steps

### Test from VM # 2 - Fail
- SSH into VM # 2
- In VM # 2, perform nslookup on storage account's FQDN
    - **Expected Result:** Resolves to private IP in private subnet
- Install nfs-common and attempt to mount the blob container
    - **Expected Result:** Timeout since this VM # 2's IP has not been whitelisted at NSG
- Exit VM # 2

## Test from VM # 1 - Pass
- SSH into VM # 1
- In VM # 1, perform nslookup on storage account's FQDN
    - **Expected Result:** Resolves to private IP in private subnet
- Install nfs-common and attempt to mount the blob container
    - **Expected Result:** Can successfully mount the container since VM # 1's IP has been whitelisted at NSG
- Exit VM # 1

## Add VM # 2 to NSG allow rule
- Add VM # 2 private IP address to NSG rule to allow connectivity
- Re-validate access
    - **Expected Result:** Can now successfully mount and read from drive