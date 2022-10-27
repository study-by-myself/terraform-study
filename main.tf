
provider "aws" {
	region = "us-east-2"
}

resource "aws_instance" "example" {
	ami	= "ami-0c55b159cbfafe1f0"
	instance_type = "t2.micro"
	vpc_security_group_ids = [aws_security_group.instance.id]

	user_data = <<-EOF
				#!/bin/bash
				echo "Hello, World" > index.html
				nohup busybox httpd -f -p ${var.server_port} &
				EOF

	tags = {
		Name = "terraform-example"
	}
}

resource "aws_security_group" "instance" {
	name = "terraform-example-instance"

	ingress {
		from_port	= var.server_port
		to_port		= var.server_port
		protocol	= "tcp"
		cidr_blocks	= ["0.0.0.0/0"]
	}
}

resource "aws_launch_configuration" "example" {
	image_id		= "ami-0c55b159cbfafe1f0"
	instance_type	= "t2.micro"
	security_groups = [aws_security_group.instance.id]

	user_data = <<-EOF
				#!/bin/bash
				echo "Hello, World" > index.html
				nohup busybox httpd -f -p ${var.server_port} &
				EOF

	# ASG에서 시작 구성을 사용할 때 필요
	lifecycle {
		create_before_destroy = true
	}
}

resource "aws_autoscaling_group" "example" {
	launch_configuration	= aws_launch_configuration.example.name
	vpc_zone_identifier		= data.aws_subnet_ids.default.ids

	target_group_arns = [aws_lb_target_group.asg.arn]
	health_check_type = "ELB"

	min_size	= 3
	max_size	= 10

	tag {
		key					= "Name"
		value				= "terraform-asg-example"
		propagate_at_launch	= true
	}
}

resource "aws_lb" "example" {
	name				= "terraform-asg-example"
	load_balancer_type	= "application"
	subnets				= data.aws_subnet_ids.default.ids
	security_groups		= [aws_security_group.alb.id]
}

resource "aws_lb_listener" "http" {
	load_balancer_arn	= aws_lb.example.arn
	port				= 80
	protocol			= "HTTP"

	# 기본값으로 단순 404 페이지 오류 반환
	default_action {
		type = "fixed-response"

		fixed_response {
			content_type	= "text/plain"
			message_body	= "404: page not found"
			status_code		= 404
		}
	}
}

resource "aws_security_group" "alb" {
	name = "terraform-example-alb"
	
	# 인바운드 HTTP 트래픽 허용
	ingress {
		from_port	= 80
		to_port		= 80
		protocol	= "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}

	# 모든 아웃바운드 트래픽 허용
	egress {
		from_port	= 0
		to_port		= 0
		protocol	= "-1"
		cidr_blocks	= ["0.0.0.0/0"]
	}
}

resource "aws_lb_target_group" "asg" {
	name		= "terraform-asg-example"
	port		= var.server_port
	protocol	= "HTTP"
	vpc_id		= data.aws_vpc.default.id

	health_check {
		path				= "/"
		protocol			= "HTTP"
		matcher				= "200"
		interval			= 15
		timeout				= 3
		healthy_threshold	= 2
		unhealthy_threshold	= 2
	}
}

resource "aws_lb_listener_rule" "asg" {
	listener_arn	= aws_lb_listener.http.arn
	priority		= 100

	condition {
		path_pattern {
			values = ["*"]
		}
	}

	action {
		type				= "forward"
		target_group_arn	= aws_lb_target_group.asg.arn
	}
}





