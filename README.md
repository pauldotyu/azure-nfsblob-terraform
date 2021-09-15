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

- Virtual network with 3 subnets
    - internal - VMs without any public IPs
    - external - VMs with public IPs
    - private - where private endpoint NIC will be placed
- Network Security Group linked to external subnet
    - Allow SSH from my public IP
- Network Security Group linked to private subnet
    - Allow any Tcp traffic from specified endpoints
    - Deny all other traffic
- Storage Account with a default deny network rule with the following exceptions:
    - My public IP
    - internal subnet
    - external subnet
- Blob storage container named "myblobs"
- Linux VMs in internal subnet
- Linux VMs in external subnet
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
    sudo mount -o sec=sys,vers=3,nolock,proto=tcp sanfsblob682.blob.core.windows.net:/sanfsblob682/myblobs  /mnt/test

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

- Create a new subnet
- Create a private endpoint for the storage account and attach it to the new subnet
- Creation of a private endpoint in the Azure Portal will also create a Azure Private DNS zone, make sure this zone is linked to your virtual network
- Set the `disable-private-endpoint-network-policies` flag to false using the following command (NOTE: this is already configured for the `private` subnet in the Terraform):
    ```sh
    # this makes the NSGs work
    az network vnet subnet update --disable-private-endpoint-network-policies false --name private --resource-group rg-nfsblob --vnet-name vn-nfsblob
    ```
- Create a new network security group and associate it with the new subnet
- Add rules as needed:
    - Allow traffic from your "approved sources" (network range, list of IPs, single IP)
    - Deny all other traffic

## Validation steps

- SSH into external VM # 2
- SSH into internal VM # 1
- In internal VM # 1, perform nslookup on storage account's FQDN
    - **Expected Result:** Resolves to private IP in private subnet
- Install nfs-common and attempt to mount the blob container
    - **Expected Result:** Timeout since this internal VM # 1's IP has not been whitelisted at NSG
- Exit internal VM # 1
- In external VM # 2, perform nslookup on storage account's FQDN
    - **Expected Result:** Resolves to private IP in private subnet
- Install nfs-common and attempt to mount the blob container
    - **Expected Result:** Timeout since this external VM # 2's IP has not been whitelisted at NSG
- Exit external VM # 2
- SSH into external VM # 1
- In external VM # 1, perform nslookup on storage account's FQDN
    - **Expected Result:** Resolves to private IP in private subnet
- Install nfs-common and attempt to mount the blob container
    - **Expected Result:** Can successfully mount the container since external VM # 1's IP has been whitelisted at NSG