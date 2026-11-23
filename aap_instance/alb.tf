# TLS certificate for the ALB, issued by ACM and validated through Route53.
# ACM renews it automatically while it is in use and the validation record stays.
# (Replaced a Let's Encrypt certificate imported into ACM, which only renewed when
# someone ran terraform apply and expired on 2026-11-22.)
resource "aws_acm_certificate" "aap" {
  count                     = var.create_alb ? 1 : 0
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = {
    Name      = var.domain_name
    Terraform = "true"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "aap_cert_validation" {
  for_each = var.create_alb ? {
    for o in aws_acm_certificate.aap[0].domain_validation_options : o.domain_name => o
  } : {}

  zone_id         = data.aws_route53_zone.hashidemos_zone[0].id
  name            = each.value.resource_record_name
  type            = each.value.resource_record_type
  records         = [each.value.resource_record_value]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "aap" {
  count                   = var.create_alb ? 1 : 0
  certificate_arn         = aws_acm_certificate.aap[0].arn
  validation_record_fqdns = [for r in aws_route53_record.aap_cert_validation : r.fqdn]
}

# ALB Security Group
resource "aws_security_group" "alb_sg" {
  count       = var.create_alb ? 1 : 0
  name        = "alb-sg"
  description = "Allow inbound HTTP/HTTPS traffic"
  vpc_id      = aws_vpc.aap_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
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
    Name      = "ALB-SG"
    Terraform = "true"
  }
}

# ALB Target Group
resource "aws_lb_target_group" "app_tg" {
  count    = var.create_alb ? 1 : 0
  name     = "aap-target-group"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.aap_vpc.id

  health_check {
    path                = "/"
    port                = "443"
    protocol            = "HTTPS"
    interval            = 180             # 5 minutes - very infrequent checks
    timeout             = 60             # 2 minutes - very generous timeout
    healthy_threshold   = 2               # Only 2 successes needed
    unhealthy_threshold = 10              # 20 failures before marking unhealthy
    matcher             = "200-499"       # Accept almost anything except 5xx server errors
  }
}

# Application Load Balancer
resource "aws_lb" "aap_alb" {
  count              = var.create_alb ? 1 : 0
  name               = "aap-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg[0].id]
  subnets = [
    aws_subnet.aap_public_subnet_az1.id,
    aws_subnet.aap_public_subnet_az2.id
  ]

  tags = {
    Name      = "AAP-ALB"
    Terraform = "true"
  }
}

# HTTPS Listener
resource "aws_lb_listener" "https" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.aap_alb[0].arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06" # TLS 1.3 and 1.2 only
  certificate_arn   = aws_acm_certificate_validation.aap[0].certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg[0].arn
  }
}

# HTTP Redirect Listener
resource "aws_lb_listener" "http_redirect" {
  count             = var.create_alb ? 1 : 0
  load_balancer_arn = aws_lb.aap_alb[0].arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

# Target Group Attachment
resource "aws_lb_target_group_attachment" "attach_instance" {
  count            = var.create_alb ? 1 : 0
  target_group_arn = aws_lb_target_group.app_tg[0].arn
  target_id        = aws_instance.aap_instance.id
  port             = 443
}

# Security Group Rule for ALB to Instance
resource "aws_security_group_rule" "alb_to_instance" {
  count                    = var.create_alb ? 1 : 0
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb_sg[0].id
  security_group_id        = aws_security_group.aap_security_group.id
}

# Route53 Data Source
data "aws_route53_zone" "hashidemos_zone" {
  count        = var.create_alb ? 1 : 0
  name         = var.route53_zone_name
  private_zone = false
}

# Route53 Record
resource "aws_route53_record" "aap_alb_dns" {
  count   = var.create_alb ? 1 : 0
  zone_id = data.aws_route53_zone.hashidemos_zone[0].id
  name    = var.domain_name
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.aap_alb[0].dns_name]
}

resource "terraform_data" "wait_for_healthy_target" {
  count   = var.create_alb ? 1 : 0
  
  provisioner "local-exec" {
    command = <<EOT
      echo "Waiting for target to become healthy..."
      for i in {1..50}; do
        status=$(aws --region ${var.aws_region} elbv2 describe-target-health \
          --target-group-arn ${aws_lb_target_group.app_tg[0].arn} \
          --query 'TargetHealthDescriptions[0].TargetHealth.State'  \
          --output text)

        echo "Current health status: $status"

        if [ "$status" = "healthy" ]; then
          echo "Target is healthy!"
          sleep 60
          exit 0
        fi

        sleep 10
      done

      echo "Timed out waiting for target to become healthy."
      exit 
    EOT
  }

  depends_on = [
    aws_instance.aap_instance,
    aws_lb_target_group.app_tg[0],
    aws_route53_record.aap_alb_dns[0]
  ]

  triggers_replace = {
    instance_id = aws_instance.aap_instance.id
    alb_arn     = aws_lb.aap_alb[0].arn
  }
} 