# Bastion Host - SSH Key Setup

## Generate SSH Key Pair

### Step 1: Generate the SSH Key

Run the following command to generate a new SSH key pair:

```bash
ssh-keygen -t rsa -b 4096 -f ~/.ssh/staging-bastion-key -C "staging-bastion"
```

This will create:
- **Private key**: `~/.ssh/staging-bastion-key` (keep this secret!)
- **Public key**: `~/.ssh/staging-bastion-key.pub` (this is what you'll use in Terraform)

### Step 2: Set Proper Permissions

Make sure the private key has the correct permissions:

```bash
chmod 600 ~/.ssh/staging-bastion-key
```

### Step 3: Get the Public Key Content

Display the public key content:

```bash
cat ~/.ssh/staging-bastion-key.pub
```

The output will look something like:
```
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... staging-bastion
```

## Using the SSH Key with Terraform

### Option 1: Using terraform.tfvars (Recommended)

Create a `terraform.tfvars` file in the bastion-host directory:

```hcl
ssh_public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC... staging-bastion"
```

Then run:
```bash
terraform init
terraform plan
terraform apply
```

### Option 2: Using Command Line Variable

```bash
terraform apply -var="ssh_public_key=$(cat ~/.ssh/staging-bastion-key.pub)"
```

### Option 3: Using Environment Variable

```bash
export TF_VAR_ssh_public_key="$(cat ~/.ssh/staging-bastion-key.pub)"
terraform apply
```

## Connecting to the Bastion Host

After the bastion host is deployed, you can connect using:

```bash
ssh -i ~/.ssh/staging-bastion-key ec2-user@bastion.staging.zing.you
```

Or using the IP address (check Terraform outputs):

```bash
ssh -i ~/.ssh/staging-bastion-key ec2-user@<PUBLIC_IP>
```

## Security Best Practices

1. **Never commit private keys** to version control
2. **Add to .gitignore**:
   ```
   *.pem
   *.key
   !*.pub
   terraform.tfvars
   ```
3. **Use SSH agent** to avoid storing keys on disk:
   ```bash
   ssh-add ~/.ssh/staging-bastion-key
   ```
4. **Rotate keys periodically** for better security

## Troubleshooting

### Permission Denied Error

If you get "Permission denied (publickey)", check:
- Private key permissions: `chmod 600 ~/.ssh/staging-bastion-key`
- Correct key file: Make sure you're using the private key, not the public key
- Key format: Ensure the public key in Terraform matches exactly what's in the `.pub` file

### Key Already Exists in AWS

If the key pair already exists in AWS, you can either:
1. Delete the existing key pair from AWS Console
2. Use a different key name by modifying the bastion-host module
3. Import the existing key pair into Terraform state

