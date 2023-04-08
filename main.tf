locals {
  region         = "eu-central-1"
  ami            = "ami-065deacbcaac64cf2"
  cidr           = "192.168.69.0/24"
  instance_count = 5

  ansible_connection_params = "ansible_user=ubuntu ansible_ssh_private_key_file=./id_rsa ansible_ssh_common_args='-o StrictHostKeyChecking=no'"
}

provider "aws" {
  region = local.region
}

# -------------------

resource "aws_vpc" "my_vpc" {
  cidr_block = local.cidr

  tags = { Name = "my_vpc" }
}

resource "aws_subnet" "my_subnet" {
  vpc_id     = aws_vpc.my_vpc.id
  cidr_block = local.cidr

  tags = { Name = "my_subnet" }
}

resource "aws_internet_gateway" "my_internet_gateway" {
  vpc_id = aws_vpc.my_vpc.id

  tags = { Name = "my_internet_gateway" }
}

resource "aws_route_table" "my_route_table" {
  vpc_id = aws_vpc.my_vpc.id

  route {
    gateway_id = aws_internet_gateway.my_internet_gateway.id
    cidr_block = "0.0.0.0/0"
  }

  tags = { Name = "my_route_table" }
}

resource "aws_route_table_association" "my_association" {
  subnet_id      = aws_subnet.my_subnet.id
  route_table_id = aws_route_table.my_route_table.id
}

# -------------------

resource "random_pet" "my_key_identifier" {}

resource "tls_private_key" "my_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "my_key" {
  key_name   = "my_key-${random_pet.my_key_identifier.id}"
  public_key = tls_private_key.my_key.public_key_openssh
}

resource "local_file" "ssh_private_key_file" {
  filename             = "./id_rsa"
  content              = tls_private_key.my_key.private_key_pem
  file_permission      = "600"
  directory_permission = "700"
}

# -------------------

resource "aws_security_group" "ssh_only" {
  name        = "ssh_and_http"
  description = "Allow SSH and HTTP inbound traffic, allow all outbound"
  vpc_id      = aws_vpc.my_vpc.id

  ingress {
    description = "SSH inbound"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP inbound"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ssh_and_http"
  }
}

resource "aws_instance" "my_instance" {
  count                       = local.instance_count
  ami                         = local.ami
  instance_type               = "t3a.nano"
  key_name                    = aws_key_pair.my_key.key_name
  vpc_security_group_ids      = [aws_security_group.ssh_only.id]
  subnet_id                   = aws_subnet.my_subnet.id
  associate_public_ip_address = true

  tags = {
    Name = "my_instance-${count.index}"
  }
}

resource "aws_ebs_volume" "my_volume" {
  count             = local.instance_count
  availability_zone = aws_subnet.my_subnet.availability_zone
  size              = 1
}

resource "aws_volume_attachment" "my_attachment" {
  count       = local.instance_count
  volume_id   = aws_ebs_volume.my_volume[count.index].id
  instance_id = aws_instance.my_instance[count.index].id
  device_name = "/dev/sdf"
}

output "instance_ips" {
  value = aws_instance.my_instance.*.public_ip
}

resource "local_file" "ansible_ip_list_file" {
  filename = "./hosts"
  content  = join("\n", [for ip in aws_instance.my_instance.*.public_ip : "${ip} ${local.ansible_connection_params}"])
}

