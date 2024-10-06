terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "4.64.0"
    }
  }
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
  key_name   = "demo2_k8s_ssh_key"
  public_key = tls_private_key.ssh_key.public_key_openssh
}


# Input the existing VPC ID (replace with the actual VPC ID)
variable "existing_vpc_id" {
  description = "ID of the existing VPC"
  default     = "vpc-080cf6872b07efacf"
}

resource "aws_subnet" "k8s_subnet" {
  vpc_id     = var.existing_vpc_id
  cidr_block = "172.31.51.0/25"
  map_public_ip_on_launch = true  # Enable Auto-Assign Public IP

  tags = {
    Name = "demo2-k8s-subnet"
  }
}

resource "aws_security_group" "k8s_sg" {
  name        = "demo2_ssh"
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
    Name = "demo-k8s-sg"
  }
} 

resource "aws_instance" "k8s_master" {
  ami           = "ami-085f9c64a9b75eed5"  # Change to your preferred AMI (e.g., Ubuntu)
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
    Name = "demo-k8s-master"
    env = "Production"
    owner = "team2"
  }
}

resource "aws_instance" "k8s_worker" {
  count         = 2
  ami           = "ami-085f9c64a9b75eed5"  # Change to your preferred AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.k8s_subnet.id
  security_groups = [aws_security_group.k8s_sg.id]
  depends_on = [aws_security_group.k8s_sg]
  associate_public_ip_address = true  # Ensure public IP is assigned
  key_name      = aws_key_pair.k8s_key.key_name

  tags = {
    Name = "demo-k8s-worker-${count.index}"
    env = "Production"
    owner = "team2"
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
