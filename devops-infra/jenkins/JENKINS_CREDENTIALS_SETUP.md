# Jenkins Credentials Setup for EC2 Deployment

This guide shows you exactly where to configure EC2 SSH credentials in Jenkins.

## Step-by-Step: Configure EC2 SSH in Jenkins

### Step 1: Access Jenkins Credentials

1. Open Jenkins in your browser: `http://<jenkins-ip>:8080`
2. Click **"Manage Jenkins"** (left sidebar)
3. Click **"Credentials"**
4. Click **"System"** (under Stores scoped to Jenkins)
5. Click **"Global credentials (unrestricted)"**
6. Click **"Add Credentials"** (left sidebar)

### Step 2: Add EC2 Host (IP Address)

1. **Kind**: Select **"Secret text"**
2. **Secret**: Enter your EC2 instance IP or hostname
   - Example: `54.123.45.67`
   - Or: `ec2-54-123-45-67.compute-1.amazonaws.com`
3. **ID**: Enter `ec2-host`
4. **Description**: `EC2 Instance Host/IP`
5. Click **"OK"**

### Step 3: Add EC2 SSH Key

1. **Kind**: Select **"SSH Username with private key"**
2. **ID**: Enter `ec2-ssh-key`
3. **Description**: `EC2 SSH Private Key`
4. **Username**: Enter `ubuntu` (for Ubuntu) or `ec2-user` (for Amazon Linux)
5. **Private Key**: Choose one:
   - **Option A**: Select **"Enter directly"** and paste your `.pem` file content
   - **Option B**: Select **"From a file on Jenkins master"** and upload the file
6. Click **"OK"**

**To get your .pem file content:**
```bash
# On your local machine
cat ~/.ssh/your-ec2-key.pem
# Copy the entire output including -----BEGIN RSA PRIVATE KEY----- and -----END RSA PRIVATE KEY-----
```

### Step 4: Add EC2 User (Optional)

1. **Kind**: Select **"Secret text"**
2. **Secret**: Enter `ubuntu` (or `ec2-user` for Amazon Linux)
3. **ID**: Enter `ec2-user`
4. **Description**: `EC2 SSH Username`
5. Click **"OK"**

### Step 5: Verify Credentials

You should now see these credentials:
- ✅ `ec2-host` (Secret text)
- ✅ `ec2-ssh-key` (SSH Username with private key)
- ✅ `ec2-user` (Secret text) - Optional
- ✅ `github-pat-token` (Secret text) - Already configured

## How Jenkins Uses These Credentials

When you run the pipeline, Jenkins will:

1. **Read `ec2-host`** to get the EC2 IP address
2. **Use `ec2-ssh-key`** to authenticate SSH connection
3. **SSH into EC2** using the credentials
4. **Clone all three repos** on EC2:
   - `aks_data_structures_devops`
   - `aks_data_structures_frontend`
   - `aks_data_structures_backend`
5. **Build Docker images** on EC2
6. **Deploy to Kubernetes** on EC2 using the deployment script

## Testing SSH Connection

Before running the pipeline, test SSH connection manually:

```bash
# On Jenkins server or your local machine
ssh -i ~/.ssh/your-ec2-key.pem ubuntu@<EC2-IP>

# If connection works, you're good to go!
```

## Troubleshooting

### "Credentials not found" Error

- Verify credential IDs match exactly: `ec2-host`, `ec2-ssh-key`, `ec2-user`
- Check credentials are in "Global credentials (unrestricted)"

### "Permission denied (publickey)" Error

- Verify SSH key is correct
- Check key permissions: `chmod 600 ~/.ssh/your-key.pem`
- Ensure username matches (ubuntu vs ec2-user)

### "Host key verification failed" Error

- The pipeline uses `-o StrictHostKeyChecking=no` to skip this
- Or manually accept host key: `ssh-keyscan <EC2-IP> >> ~/.ssh/known_hosts`

### "Connection refused" Error

- Check EC2 security group allows SSH (port 22) from Jenkins IP
- Verify EC2 instance is running
- Check EC2 IP address is correct

## Alternative: Jenkins on EC2

If Jenkins is running **on the same EC2 instance**:

1. **Don't configure EC2 SSH credentials** (not needed)
2. The pipeline will run directly on EC2
3. Just ensure:
   - `kubectl` is installed and configured
   - `docker` is installed and running
   - User has permissions to run docker and kubectl

## Security Best Practices

1. ✅ **Use SSH keys** instead of passwords
2. ✅ **Restrict SSH access** in EC2 security group to Jenkins IP only
3. ✅ **Rotate SSH keys** regularly
4. ✅ **Use IAM roles** for EC2 instead of access keys
5. ✅ **Never commit** SSH keys to git

---

**Next Step**: Run the `main-pipeline` in Jenkins to deploy!

