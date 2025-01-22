# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"
}

# Création du VPC

resource "aws_vpc" "VPC-Fargate" {
  cidr_block = "10.8.0.0/16"
  tags = {
    Name = "Fargate-VPC"
  }
}

# Création des sous-réseaux publics

resource "aws_subnet" "Sub-1" {
  vpc_id     = aws_vpc.VPC-Fargate.id
  cidr_block = "10.8.1.0/24"
  availability_zone = "us-east-1a"

}

resource "aws_subnet" "Sub-2" {
  vpc_id     = aws_vpc.VPC-Fargate.id
  cidr_block = "10.8.2.0/24"
  availability_zone = "us-east-1b"

}
# Création de l'Internet Gateway
resource "aws_internet_gateway" "IGW-FG" {
  vpc_id = aws_vpc.VPC-Fargate.id

  tags = {
    Name = "IGW"
  }
}

# Création de la table de routage
resource "aws_route_table" "FG-Table" {
  vpc_id = aws_vpc.VPC-Fargate.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.IGW-FG.id
  }

  tags = {
    Name = "T_FG"
  }
}

# Association des sous-réseaux à la table de routage
resource "aws_route_table_association" "Ass1" {
  subnet_id      = aws_subnet.Sub-1.id
  route_table_id = aws_route_table.FG-Table.id
}

resource "aws_route_table_association" "Ass2" {
  subnet_id      = aws_subnet.Sub-2.id
  route_table_id = aws_route_table.FG-Table.id
}

# Création du Security Group

resource "aws_security_group" "Aut_http" {
  name        = "Aut_http"
  description = "AUT HTTP traffic"
  vpc_id      = aws_vpc.VPC-Fargate.id

  ingress {
    description = "HTTP"
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
    Name = "AUTH_http"
  }
}

resource "aws_ecr_repository" "app_Farg" {
  name                 = "my-app-farg"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

# 3. Cluster Fargate et Task Definition

resource "aws_ecs_cluster" "Cluster_Farg1" {
  name = "Farg1-cluster"
}

resource "aws_ecs_task_definition" "Farg_task" {
  family                   = "service"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = "arn:aws:iam::591688565785:role/LabRole"
  

  container_definitions = jsonencode([{
    name  = "app-container"
    image = "591688565785.dkr.ecr.us-east-1.amazonaws.com/my-app-farg:latest"
    portMappings = [{
      containerPort = 80
      hostPort      = 80
    }]
  }])
}

# 4. Application Load Balancer

resource "aws_lb" "app_lb" {
  name               = "app-lb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.Aut_http.id]
  subnets            = [aws_subnet.Sub-1.id, aws_subnet.Sub-2.id]
}

resource "aws_lb_target_group" "app_tg" {
  name        = "app-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.VPC-Fargate.id
  target_type = "ip"

  health_check {
    healthy_threshold   = "3"
    interval            = "30"
    protocol            = "HTTP"
    matcher             = "300"
    timeout             = "3"
    path                = "/"
    unhealthy_threshold = "2"
  }
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.app_lb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# Service ECS
resource "aws_ecs_service" "app_service" {
  name            = "app-service"
  cluster         = aws_ecs_cluster.Cluster_Farg1.id
  task_definition = aws_ecs_task_definition.Farg_task.arn
  launch_type     = "FARGATE"
  desired_count   = 1

  network_configuration {
    subnets          = [aws_subnet.Sub-1.id, aws_subnet.Sub-2.id]
    assign_public_ip = true
    security_groups  = [aws_security_group.Aut_http.id]
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "app-container"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.front_end]
}
