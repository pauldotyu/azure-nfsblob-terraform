# azure-nfsblob-terraform

This repo will provision an environment to demonstrate how to mount Azure Blob containers using NFSv3.

If you want to use this repo, you'll need to do the following:

> This repo assumes you are in a native Linux OS or WSL2

1. Have Terraform locally installed
1. Optionally, have a Terraform Cloud account
    - If you do not want to use Terraform Cloud for remote state you can simply remove or comment out all the contents in [backend.tf](./backend.tf)
    - If you do have a Terraform Cloud account:
      - Make sure to update [backend.tf](./backend.tf) to point to your `organization` and `workspace`
      - Make sure your workspace settings is set to **Local** as the **Execution Mode** (we'll only use this for remote state)
      - Login into the account using the `terraform login` command
1. Have Azure CLI locally installed
1. Log into Azure using `az login` command
1. This deployment leverages your SSH public key on your local machine, make sure you have run `ssh-keygen` to generate your key pair
1. Run `terraform apply` and confirm the deployment
1. The public IP of the virtual machine is listed in the output, you can `ssh` using that
1. SSH into the VM, install `nfs-common`, and mount the drive

    ```sh
    # upgrade and install
    sudo apt update
    sudo apt install nfs-common

    # create a new mount point
    sudo mkdir /mnt/test

    # mount the drive make sure your storage account name is updated in the command below
    sudo mount -o sec=sys,vers=3,nolock,proto=tcp sanfsblob243.blob.core.windows.net:/sanfsblob243/myblobs  /mnt/test

    # assume ownership
    sudo chown -R $USER /mnt/test

    # test the mount
    touch /mnt/test/myfile.txt
    ls /mnt/test
    ```