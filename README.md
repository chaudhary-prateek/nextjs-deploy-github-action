# 🚀 **Next.js App Deployment Notes (EC2 + Docker + ECR + NGINX + GitHub Actions + Semantic Release)**

---

## 🖥️ **1. Launch EC2 Instance**

* Choose Ubuntu 22.04 (or preferred).
* Create and download a new `.pem` key pair.
* Allow inbound rules for:

  * SSH (22)
  * HTTP (80)
  * Custom App Port (e.g., 3000)

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

* Attach this policy to an **IAM User**
* Generate **Access Key ID** and **Secret Key** for GitHub Secrets

---

## 🧪 **7. GitHub Workflows Overview**

### 🔄 `release.yml`: Semantic Release (Triggered on push to `main` or `dev`)

> ✅ View this in the actual file: `.github/workflows/release.yml`

---

### 🚀 `deploy.yml`: Build + Deploy to EC2 (Triggered on push to `main`, `dev`, `aws`, but only deploys if release is from `main`)

> ✅ View this in the actual file: `.github/workflows/deploy.yml`

---

## 🔐 **8. GitHub Secrets**

| Secret Name                                      | Description                                |
| ------------------------------------------------ | ------------------------------------------ |
| `AWS_ACCESS_KEY_ID`                              | From IAM user                              |
| `AWS_SECRET_ACCESS_KEY`                          | From IAM user                              |
| `AWS_REGION`                                     | e.g. `ap-south-1`                          |
| `ECR_REPO`                                       | Full ECR repo URI                          |
| `EC2_HOST`                                       | EC2 Public IP                              |
| `EC2_USER`                                       | Usually `ubuntu`                           |
| `EC2_SSH_KEY`                                    | EC2 `.pem` file contents as string         |
| `APP_DIR`                                        | Path where app is hosted (`/var/www/html`) |
| `NEXT_PUBLIC_API_BASE_URL`                       | Frontend API Base URL                      |
| `NEXT_PUBLIC_LOCALSTORAGE_ENCRYPTION_SECRET_KEY` | Secret key used in frontend storage        |

---

## ✅ Done!

Now, every push to `main` will:

1. Run semantic release.
2. Build the Docker image with the new tag.
3. Push to ECR.
4. SSH into EC2.
5. Pull & run new container.
6. Rollback if failure occurs.
