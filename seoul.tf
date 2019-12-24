# Variables needed to the infrastructure
variable "region" {
  description = "Which aws region to create the infrastructure"
  default     = "ap-northeast-2" # ap-northeast-2 = Asia Pacific (Seoul)
}
variable "vpc_cidr_block" {
  description = "Big IPs block for the VPC network"
  default     = "172.23.0.0/20"
}
variable "env" {
  description = "Prefix for tagging different environments"
  default     = "Seoul"
}
variable "ecs_iam_role" {
  description = "The ARN of the IAM role that allows Application AutoScaling to modify scalable targets"
  default = "arn:aws:iam::688980480079:role/ecsTaskExecutionRole"
}

# Provider definition
provider "aws" {
  version = "~> 2.0"
  region  = var.region
}

# Getting a list of AZs in the selected region
data "aws_availability_zones" "available" {}

# VPC creation
resource "aws_vpc" "vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_hostnames = true

  tags = {
    Name = "${var.env} - VPC"
  }
}

/*# Elastic IP NAT Gateway - One for each private subnet / NAT Gateway
resource "aws_eip" "eip_nat_gateway" {
  count = length(aws_subnet.public_subnet)

  tags = {
    Name = "${var.env} - EIP NAT Gateway AZ${count.index}"
  }
}*/

/*# NAT Gateway - One for each private subnet
resource "aws_nat_gateway" "nat_gateway" {
  count         = length(aws_subnet.public_subnet)
  allocation_id = aws_eip.eip_nat_gateway[count.index].id
  subnet_id     = aws_subnet.public_subnet[count.index].id

  tags = {
    Name = "${var.env} - NAT Gateway AZ${count.index}"
  }
}*/

# Internet Gateway - For the entire VPC
resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.env} - Internet Gateway"
  }
}

# Default route table restricted to internal VPC communication only
resource "aws_default_route_table" "default_route_table" {
  default_route_table_id = aws_vpc.vpc.default_route_table_id

  tags = {
    Name = "${var.env} - Default Route Table"
  }
}

# Private route tables for subnets with internet access via nat gateway - One for each private subnet/nat gateway
resource "aws_route_table" "private_route_table" {
  vpc_id = aws_vpc.vpc.id
  count  = length(aws_subnet.public_subnet)

  /*route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gateway[count.index].id
  }*/

  tags = {
    Name = "${var.env} - Private Route Table AZ${count.index}"
  }
}

# Public route table with direct internet access via internet gateway
resource "aws_route_table" "public_route_table" {
  vpc_id = aws_vpc.vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.internet_gateway.id
  }

  tags = {
    Name = "${var.env} - Public Route Table"
  }
}

# Default DHCP Options
resource "aws_default_vpc_dhcp_options" "dhcp_options_set" {
  tags = {
    Name = "${var.env} - DHCP Options Set"
  }
}

# Default network ACL - Private subnets
resource "aws_default_network_acl" "private_network_acl" {
  default_network_acl_id = aws_vpc.vpc.default_network_acl_id

  tags = {
    Name = "${var.env} - Private Network ACL (Default)"
  }

  subnet_ids = aws_subnet.private_subnet[*].id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.vpc.cidr_block  # Regra ideal para a rede ficar fechada
    #cidr_block = "0.0.0.0/0"              # É necessário caso alguma instância precise sair pelo gateway nat
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = aws_vpc.vpc.cidr_block
    #cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  # Workaround para o problema "network_acl will be updated in-place"
  #lifecycle {
  #  ignore_changes = [subnet_ids]
  #}
}

# Configurações da ACL de subredes publicas
resource "aws_network_acl" "public_network_acl" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.env} - Public Network ACL"
  }

  subnet_ids = aws_subnet.public_subnet[*].id

  ingress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  egress {
    protocol   = -1
    rule_no    = 100
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }
}

# Security Groups
resource "aws_default_security_group" "default_security_group" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Name = "${var.env} - Default Security Group"
  }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = [var.vpc_cidr_block]
  }

  egress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "all_access_security_group" {
  name        = "Allow ingress of everything from anywhere"
  description = "Allow ingress of everything from anywhere"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name      = "${var.env} - Allow ingress of everything from anywhere"
  }

  ingress {
    protocol    = -1
    from_port   = 0
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_http_and_https_ingress" {
  name        = "Allow HTTP and HTTPS ingress"
  description = "Allow HTTP and HTTPS ingress"
  vpc_id      = aws_vpc.vpc.id

  tags = {
    Name      = "${var.env} - Allow HTTP and HTTPS ingress"
  }

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    to_port     = 80
  }

  ingress {
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 443
    to_port     = 443
  }
}

# Public subnets - one for each AZ
resource "aws_subnet" "public_subnet" {
  vpc_id            = aws_vpc.vpc.id
  count             = length(data.aws_availability_zones.available.names)
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 4, (count.index + 1))
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name            = "${var.env} - Public Subnet AZ${count.index}"
  }
}

# Private subnets - one for each AZ
resource "aws_subnet" "private_subnet" {
  vpc_id            = aws_vpc.vpc.id
  count             = length(data.aws_availability_zones.available.names)
  cidr_block        = cidrsubnet(aws_vpc.vpc.cidr_block, 4, (count.index + 11))
  availability_zone = element(data.aws_availability_zones.available.names, count.index)

  tags = {
    Name            = "${var.env} - Private Subnet AZ${count.index}"
  }
}

# Associating public subnets to route table
resource "aws_route_table_association" "public_rt_association" {
  count          = length(aws_subnet.public_subnet)
  subnet_id      = aws_subnet.public_subnet[count.index].id
  route_table_id = aws_route_table.public_route_table.id
}

# Associating private subnets to route tables
resource "aws_route_table_association" "private_rt_association" {
  count          = length(aws_subnet.private_subnet)
  subnet_id      = aws_subnet.private_subnet[count.index].id
  route_table_id = aws_route_table.private_route_table[count.index].id
}

# And now stuff starts to get real...

# Elastic IP Application Load Balancer
resource "aws_eip" "eip_app_load_balancer" {
  tags = {
    Name     = "${var.env} - EIP App Load Balancer"
  }
}

# Application Load Balancer
resource "aws_lb" "alb" {
  name                       = "${var.env}-Application-Load-Balancer"
  internal                   = false
  load_balancer_type         = "application"
  security_groups            = [aws_security_group.allow_http_and_https_ingress.id,aws_default_security_group.default_security_group.id]
  subnets                    = aws_subnet.public_subnet[*].id
  enable_deletion_protection = false

  tags = {
    Name = "${var.env} - Application Load Ballancer"
  }
}

# ALB Listener
resource "aws_lb_listener" "whoami" {
  load_balancer_arn = aws_lb.alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Seoul Application Load Balancer - Moinho Sul"
      status_code  = "200"
    }
  }
}

/*# Target Group
resource "aws_lb_target_group" "whoami-target-group" {
  name        = "${var.env}-Whoami-Target-Group"
  port        = 80
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = aws_vpc.vpc.id
}*/

/*# Target Group attachments                                          #
resource "aws_lb_target_group_attachment" "whoami-targets" {         #
  target_group_arn = aws_lb_target_group.whoami-target-group.arn    ###########################################################
  target_id        = aws_instance.test.id                            #
  port             = 80                                               #
}*/

# Cluster ECS
resource "aws_ecs_cluster" "ecs_cluster" {
  name = "${var.env}-ECS-Cluster"
}

# Task Definition
resource "aws_ecs_task_definition" "whoami" {
  family                   = "${var.env}-Whoami"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::688980480079:role/ecsTaskExecutionRole"
  container_definitions    = file("service.json")
}

/*# Task Definition
resource "aws_ecs_task_definition" "zabbix" {
  family                   = "${var.env}-Zabbix"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::688980480079:role/ecsTaskExecutionRole"
  container_definitions    = file("zabbix.json")
}*/

# Service Public
resource "aws_ecs_service" "whoami" {
  name            = "${var.env}-Whoami"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.whoami.arn
  desired_count   = 3
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public_subnet[*].id
    assign_public_ip = true # da pra remover se a imagem estiver no ECR
    security_groups  = [aws_security_group.all_access_security_group.id, aws_default_security_group.default_security_group.id]
  }

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# Auto Scaling Target
resource "aws_appautoscaling_target" "ecs_target" {
  max_capacity       = 4
  min_capacity       = 1
  resource_id        = "service/${aws_ecs_cluster.ecs_cluster.name}/${aws_ecs_service.whoami.name}"
  role_arn           = var.ecs_iam_role
  scalable_dimension = "ecs:service:DesiredCount"
  service_namespace  = "ecs"
}

# Auto Scaling Policy
resource "aws_appautoscaling_policy" "ecs_policy" {
  name               = "${var.env}-AS-New-Target-Tracking-TS"
  policy_type        = "TargetTrackingScaling"
  resource_id        = aws_appautoscaling_target.ecs_target.resource_id
  scalable_dimension = aws_appautoscaling_target.ecs_target.scalable_dimension
  service_namespace  = aws_appautoscaling_target.ecs_target.service_namespace

  target_tracking_scaling_policy_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ALBRequestCountPerTarget"
      resource_label         = "app/Seoul-Application-Load-Balancer/8c810ffb8d14b025/"
    }

    target_value       = 8
    scale_in_cooldown  = 30
    scale_out_cooldown = 30
  }

  /*step_scaling_policy_configuration {
    adjustment_type         = "ChangeInCapacity"
    cooldown                = 60
    metric_aggregation_type = "Maximum"

    step_adjustment {
      metric_interval_upper_bound = 0
      scaling_adjustment          = -1
    }
  }*/
}

/*# Service Zabbix
resource "aws_ecs_service" "zabbix" {
  name            = "${var.env}-Zabbix"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.zabbix.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.public_subnet[*].id
    assign_public_ip = true
    security_groups  = [aws_security_group.all_access_security_group.id, aws_default_security_group.default_security_group.id]
  }
}*/

/*# Service Private
resource "aws_ecs_service" "whoami_private" {
  name            = "${var.env}-Whoami-Private"
  cluster         = aws_ecs_cluster.ecs_cluster.id
  task_definition = aws_ecs_task_definition.whoami.arn
  desired_count   = 3
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = aws_subnet.private_subnet[*].id
    security_groups  = [aws_security_group.all_access_security_group.id, aws_default_security_group.default_security_group.id]
  }
}*/

# TODO
# "Endpoints" pra conexão com S3 e DynamoDB
# VPN com a rede da empresa via USG
# PrivateLink ECS ECR pra melhorar a segurança da network acl da subnet privada
# Verificar: vpc peering
