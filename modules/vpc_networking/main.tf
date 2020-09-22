provider "aws" {
  region = var.region
}

resource "aws_vpc" "module_vpc" {
  cidr_block = var.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "first-vpc"
  }
}

resource "aws_subnet" "public_subnet_1" {
  cidr_block = var.public_subnet_1_cidr
  vpc_id = aws_vpc.module_vpc.id
  availability_zone = "${var.region}a"

  tags = {
    Name = "Public-Subnet-1"
  }
}

resource "aws_subnet" "public_subnet_2" {
  cidr_block = var.public_subnet_2_cidr
  vpc_id = aws_vpc.module_vpc.id
  availability_zone = "${var.region}b"

  tags = {
    Name = "Public-Subnet-2"
  }
}

resource "aws_subnet" "private_subnet_1" {
  cidr_block = var.private_subnet_1_cidr
  vpc_id = aws_vpc.module_vpc.id
  availability_zone = "${var.region}a"

  tags = {
    Name = "Private-Subnet-1"
  }
}

resource "aws_subnet" "private_subnet_2" {
  cidr_block = var.private_subnet_2_cidr
  vpc_id = aws_vpc.module_vpc.id
  availability_zone = "${var.region}b"

  tags = {
    Name = "Private-Subnet-2"
  }
}

resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.module_vpc.id 
  tags = {
    Name = "Public-Route-Table"
  }
}

resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.module_vpc.id
  tags = {
    Name = "Private-Route-Table"
  }
}

resource "aws_route_table_association" "public_subnet_1_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id = aws_subnet.public_subnet_1.id
}

resource "aws_route_table_association" "public_subnet_2_association" {
  route_table_id = aws_route_table.public_route_table.id
  subnet_id = aws_subnet.public_subnet_2.id
}

resource "aws_route_table_association" "private_subnet_1_association" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id = aws_subnet.private_subnet_1.id
}

resource "aws_route_table_association" "private_subnet_2_association" {
  route_table_id = aws_route_table.private_route_table.id
  subnet_id = aws_subnet.private_subnet_2.id
}

resource "aws_eip" "elastic_ip_for_nat_gw" {
  vpc = true
  associate_with_private_ip = var.eip_association_address
  
  tags = {
    Name = "EIP"
  }
}

resource "aws_nat_gateway" "nat_gateway" {
  allocation_id = aws_eip.elastic_ip_for_nat_gw.id
  subnet_id = aws_subnet.public_subnet_1.id
  
  tags = {
    Name = "NAT-GW"
  }
}

resource "aws_route" "nat_gateway_route" {
  route_table_id = aws_route_table.private_route_table.id
  nat_gateway_id = aws_nat_gateway.nat_gateway.id
  destination_cidr_block = "0.0.0.0/0"
}


/** VPC Peering Route Start **/
data "aws_vpc_peering_connection" "vpc_peering_connection_1" {
  vpc_id          = aws_vpc.module_vpc.id
  peer_cidr_block = var.peer_vpc_cidr
}

resource "aws_route" "peering_1_route" {
  route_table_id = aws_route_table.private_route_table.id
  vpc_peering_connection_id  = data.aws_vpc_peering_connection.vpc_peering_connection_1.id
  destination_cidr_block = var.peer_vpc_cidr
}

/** VPC Peering Route End **/

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.module_vpc.id
  
  tags = {
    Name="IGW"
  }
}

resource "aws_route" "igw_route" {
  route_table_id = aws_route_table.public_route_table.id
  gateway_id = aws_internet_gateway.internet_gateway.id
  destination_cidr_block = "0.0.0.0/0"
}

data "aws_ami" "ubuntu_latest" {
  owners = [var.ami_owner_id]
  most_recent = true
  
  filter {
    name = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "public-ec2-instance" {
  ami = data.aws_ami.ubuntu_latest.id
  instance_type = var.ec2_instance_type
  key_name = var.ec2_keypair
  vpc_security_group_ids = [aws_security_group.ec2-security-group.id]
  subnet_id = aws_subnet.public_subnet_1.id
}

resource "aws_security_group" "ec2-security-group" {
  name = "EC2-Instance-SG"
  vpc_id = aws_vpc.module_vpc.id
  
  ingress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port = 0
    protocol = "-1"
    to_port = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "public-nlb" {
  name               = "public-nlb"
  internal           = false
  load_balancer_type = "network"
  subnets            = ["${aws_subnet.public_subnet_1.id}", "${aws_subnet.public_subnet_2.id}"]

  enable_deletion_protection = true

  tags = {
    Name = "public-nlb"
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "nlb-target-group-dev" {
  name     = "target-group-dev"
  port     = 80
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = "${aws_vpc.module_vpc.id}"
}

resource "aws_lb_target_group" "nlb-target-group-qa" {
  name     = "target-group-qa"
  port     = 8080
  protocol = "TCP"
  target_type = "ip"
  vpc_id   = "${aws_vpc.module_vpc.id}"
}

resource "aws_lb_listener" "nlb-listener-dev" {
  load_balancer_arn = "${aws_lb.public-nlb.arn}"
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.nlb-target-group-dev.arn}"
  }
}

resource "aws_lb_listener" "nlb-listener-qa" {
  load_balancer_arn = "${aws_lb.public-nlb.arn}"
  port              = "8080"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = "${aws_lb_target_group.nlb-target-group-qa.arn}"
  }
}


output "vpc_cidr" {
  value = aws_vpc.module_vpc.cidr_block
}

output "public_subnet_1_cidr" {
  value = aws_subnet.public_subnet_1.cidr_block
}

output "private_subnet_1_cidr" {
  value = aws_subnet.private_subnet_1.cidr_block
}

output "vpc_id" {
  value = aws_vpc.module_vpc.id
}