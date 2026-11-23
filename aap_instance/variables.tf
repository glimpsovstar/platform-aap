variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "ap-southeast-2"
}

variable "ami_id" {
  description = "AMI ID for the EC2 instance"
  type        = string
}

variable "create_alb" {
  description = "Whether to create ALB, ACME certificate, and Route53 resources"
  type        = bool
  default     = true
}

variable "acme_email" {
  description = "Email address for Let's Encrypt registration"
  type        = string
}

variable "domain_name" {
  description = "Primary domain name for the certificate"
  type        = string
}

variable "subject_alternative_names" {
  description = "Optional SANs (Subject Alternative Names) for the certificate"
  type        = list(string)
  default     = []
}

variable "route53_zone_name" {
  description = "The name of the Route 53 hosted zone to use (must end with a dot)"
  type        = string
}

variable "instance_type" {
  description = "EC2 type for the AAP controller. Changing it stops and starts the instance."
  type        = string
  default     = "m6a.xlarge"
}

variable "ssh_allowed_cidrs" {
  description = "CIDRs allowed to SSH to the AAP instance. Empty means no inbound SSH."
  type        = list(string)
  default     = []
}
