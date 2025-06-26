# 🚀 **Next.js App Deployment Notes (EC2 + Docker + ECR + NGINX + GitHub Actions)**

---

## 🖥️ **1. Launch EC2 Instance**
- Choose Ubuntu 22.04 (or preferred).
- Create and download a new `.pem` key pair.
- Allow inbound rules for:
  - SSH (22)
  - HTTP (80)
  - Custom App Port (e.g., 3000)

---

## 🐳 **2. Install Docker**
```bash
sudo apt update
sudo apt install -y docker.io
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER
newgrp docker  # Or reboot the instance
```

---

## ☁️ **3. Install AWS CLI**
```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install unzip
unzip awscliv2.zip
sudo ./aws/install
```

---

## 🌐 **4. Install and Configure NGINX**
```bash
sudo apt update
sudo apt install nginx -y
sudo systemctl enable nginx
sudo nano /etc/nginx/sites-available/default
```

**Paste this config** (change port if needed):
```nginx
server {
    listen 80;
    server_name _;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

Then run:
```bash
sudo nginx -t
sudo systemctl restart nginx
```

---

## 🔐 **5. Attach EC2 Role for ECR Access**

### 🎯 **Create IAM Policy: EC2ECRPullPolicy**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRPullFromEC2",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage"
      ],
      "Resource": "*"
    }
  ]
}
```
Attach this policy to an **EC2 Role**, and attach that role to your EC2 instance.

---

## 👤 **6. Create IAM User for GitHub Access**
### 🔐 **Create IAM Policy: GitHubECRPushPolicy**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "ECRAccess",
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload",
        "ecr:ListImages",
        "ecr:DescribeImages",
        "ecr:DescribeRepositories"
      ],
      "Resource": "*"
    }
  ]
}
```
- Attach this policy to an **IAM User**
- Generate **Access Key ID** and **Secret Key** for GitHub Secrets

---

## 🧪 **7. GitHub Actions Workflow**

### `.github/workflows/deploy.yml`
```yaml
name: Build and Deploy Next.js App via ECR

on:
  push:
    branches:
      - main
      - dev

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v3

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ secrets.AWS_REGION }}

      - name: Login to Amazon ECR
        uses: aws-actions/amazon-ecr-login@v1

      - name: Build, tag, and push Docker image
        env:
          ECR_REPO: ${{ secrets.ECR_REPO }}
        run: |
          IMAGE_TAG=latest
          docker build -t $ECR_REPO:$IMAGE_TAG .
          docker push $ECR_REPO:$IMAGE_TAG
          echo "IMAGE_TAG=$IMAGE_TAG" >> $GITHUB_ENV

      - name: Add SSH key
        run: |
          echo "${{ secrets.EC2_SSH_KEY }}" > key.pem
          chmod 600 key.pem

      - name: Deploy on EC2
        run: |
          ssh -i key.pem -o StrictHostKeyChecking=no ${{ secrets.EC2_USER }}@${{ secrets.EC2_HOST }} << EOF
            set -e
            export AWS_REGION="${{ secrets.AWS_REGION }}"
            export IMAGE_TAG="${{ env.IMAGE_TAG }}"
            export ECR_REPO="${{ secrets.ECR_REPO }}"

            aws ecr get-login-password --region \$AWS_REGION | docker login --username AWS --password-stdin \$ECR_REPO

            cd ${{ secrets.APP_DIR }}

            echo "⏮️ Backing up current container..."
            if docker inspect nextjs-app &> /dev/null; then
              docker commit nextjs-app nextjs-app:backup || true
            fi

            echo "⬇️ Pulling new image..."
            docker pull \$ECR_REPO:\$IMAGE_TAG

            echo "🚀 Running new container..."
            docker stop nextjs-app || true
            docker rm nextjs-app || true

            docker run -d --name nextjs-app -p 3000:3000 \$ECR_REPO:\$IMAGE_TAG || {
              echo "❌ Deployment failed! Rolling back..."
              docker run -d --name nextjs-app -p 3000:3000 nextjs-app:backup
            }
          EOF
```

---

## 🔐 **8. Add GitHub Secrets**

| Secret Name           | Description                                |
|------------------------|--------------------------------------------|
| `AWS_ACCESS_KEY_ID`    | From IAM user                              |
| `AWS_SECRET_ACCESS_KEY`| From IAM user                              |
| `AWS_REGION`           | e.g. `ap-south-1`                          |
| `ECR_REPO`             | Full ECR repo URI                          |
| `EC2_HOST`             | EC2 Public IP                              |
| `EC2_USER`             | Usually `ubuntu`                           |
| `EC2_SSH_KEY`          | EC2 `.pem` file contents as string         |
| `APP_DIR`              | Path where app is hosted (e.g., `/var/www/html`) |

---

## ✅ Done!

Now, every push to `main` or `dev` will:
1. Build the Docker image.
2. Push to Amazon ECR with the `latest` tag.
3. SSH into EC2 and deploy the new container.
4. If deployment fails, auto-rollback to the previous image.
