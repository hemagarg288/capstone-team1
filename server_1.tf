#terraform {
#  required_providers {
#    aws = { 
#      region = "us-east-1" # Change to your desired region 
#      access_key = "AKIAXJBKQHUUI3PWY2NV" 
#      secret_key = "eSJ1+8tPhcMjrK2Ptms/P97ygcnZkwpY7ofrVJea"
#    }
#  }
#}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"  # Adjust version as needed
    }
  }

#  required_version = ">= 0.12"  # Specify the Terraform version if needed
}

provider "aws" {
  region     = "us-east-1"  # Replace with your desired region
  access_key = "AKIAXJBKQHUUI3PWY2NV" #var.aws_access_key  # Optional: use environment variables or a credentials file
  secret_key = "eSJ1+8tPhcMjrK2Ptms/P97ygcnZkwpY7ofrVJea"  #var.aws_secret_key  # Optional: same as above
}

provider "tls" {}

# Generate the SSH key pair
resource "tls_private_key" "ssh_key" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "local_file" "private_key" {
  content  = tls_private_key.ssh_key.private_key_pem
  filename = "/root/terraform/private_key.pem"
  file_permission = "0600"
}

resource "local_file" "public_key" {
  content  = tls_private_key.ssh_key.public_key_openssh
  filename = "/root/terraform/public_key.pub"
}

resource "aws_key_pair" "k8s_key" {
  key_name   = "k8s_team1_key1"
  public_key = tls_private_key.ssh_key.public_key_openssh
}


# Input the existing VPC ID (replace with the actual VPC ID)
variable "existing_vpc_id" {
  description = "ID of the existing VPC"
  default     = "vpc-0f56d0e7e00050f3b"
}

resource "aws_subnet" "k8s_subnet" {
  vpc_id     = var.existing_vpc_id
  cidr_block = "10.0.12.0/24"
  map_public_ip_on_launch = true  # Enable Auto-Assign Public IP

  tags = {
    Name = "k8s-team1-subnet1"
  }
}

resource "aws_security_group" "k8s_sg" {
  name        = "team1_sg_ssh2"
  description = "Allow SSH inbound traffic"
  vpc_id      = var.existing_vpc_id 

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # http
  }

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Restrict for security in production - https
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All protocols
    cidr_blocks = ["0.0.0.0/0"]  # Allow traffic from any IP
  }

   # Optional: Add egress rules to allow outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"  # All protocols
    cidr_blocks = ["0.0.0.0/0"]  # Allow all outbound traffic
  }
  
# Add more ingress rules as necessary for your setup

  tags = {
    Name = "team1-k8s-sg2"
  }
} 

resource "aws_instance" "k8s_master" {
  ami           = "ami-0866a3c8686eaeeba"  # Change to your preferred AMI (e.g., Ubuntu)
  instance_type = "t2.medium"
  subnet_id     = aws_subnet.k8s_subnet.id
  security_groups = [aws_security_group.k8s_sg.id]
  depends_on = [aws_security_group.k8s_sg]
  associate_public_ip_address = true  # Ensure public IP is assigned
  key_name      = aws_key_pair.k8s_key.key_name

  root_block_device {
    volume_size = 20  # Increase the size to your desired size in GiB
    #volume_type = "gp2"  # You can specify the volume type as needed
  }

  tags = {
    Name = "team1-k8s-master"
    env = "Production"
    owner = "team1"
  }
}

resource "aws_instance" "k8s_worker" {
  count         = 2
  ami           = "ami-0866a3c8686eaeeba"  # Change to your preferred AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.k8s_subnet.id
  security_groups = [aws_security_group.k8s_sg.id]
  depends_on = [aws_security_group.k8s_sg]
  associate_public_ip_address = true  # Ensure public IP is assigned
  key_name      = aws_key_pair.k8s_key.key_name

  tags = {
    Name = "team1-k8s-worker-${count.index}"
    env = "Production"
    owner = "team1"
  }
}

output "master_ip" {
  value = aws_instance.k8s_master.private_ip
}

output "worker_ips" {
  value = aws_instance.k8s_worker[*].private_ip
}

# Create the inventory content
locals {
  master_ip = aws_instance.k8s_master.private_ip

  worker_ips = join("\n", [for worker in aws_instance.k8s_worker : "${worker.private_ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/root/terraform/private_key.pem" ])
  
  inventory_content = <<EOT
[k8s_master]
${local.master_ip} ansible_ssh_user=ubuntu ansible_ssh_private_key_file=/root/terraform/private_key.pem

[k8s_worker]
${local.worker_ips}
EOT
}

resource "local_file" "inventory" {
  filename = "/root/terraform/inventory.ini"

  content = local.inventory_content
}
