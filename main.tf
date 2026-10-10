# =============================================================================
# Terraform multi-environment stack — ONE file shape for dev/staging/prod.
# Copy this to envs/<name>/main.tf, change the backend key + tfvars, done.
# Shared logic lives in ../../modules/*; this file only wires + configures.
# =============================================================================

terraform {
  required_version = ">= 1.9.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state: one S3 key per environment, DynamoDB for apply-time locking.
  # Swap "dev" for "staging"/"prod" when copying this stack.
  backend "s3" {
    bucket         = "acme-terraform-state"
    key            = "envs/dev.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "acme-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project     = "acme-platform"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# ---------------------------------------------------------------------------
# Per-environment sizing. The ONLY place dev/staging/prod differ.
# Keep this map small — anything bigger belongs in a *.tfvars file.
# ---------------------------------------------------------------------------
locals {
  sizing = {
    dev = {
      az_count      = 1
      instance_type = "t3.small"
      min_capacity  = 1
      max_capacity  = 2
      db_class      = "db.t3.micro"
      multi_az      = false
      backup_days   = 0
    }
    staging = {
      az_count      = 2
      instance_type = "m6i.large"
      min_capacity  = 2
      max_capacity  = 4
      db_class      = "db.m6i.large"
      multi_az      = true
      backup_days   = 7
    }
    prod = {
      az_count      = 3
      instance_type = "m6i.large"
      min_capacity  = 3
      max_capacity  = 9
      db_class      = "db.m6i.xlarge"
      multi_az      = true
      backup_days   = 30
    }
  }

  cfg = local.sizing[var.environment]
}

# ---------------------------------------------------------------------------
# Module calls — identical across environments, driven by local.cfg.
# ---------------------------------------------------------------------------
module "network" {
  source = "../../modules/vpc"

  name               = var.environment
  cidr_block         = var.vpc_cidr
  availability_zones = local.cfg.az_count
}

module "app" {
  source = "../../modules/compute"

  name          = "${var.environment}-web"
  subnet_ids    = module.network.private_subnet_ids
  instance_type = local.cfg.instance_type
  min_capacity  = local.cfg.min_capacity
  max_capacity  = local.cfg.max_capacity
}

module "db" {
  source = "../../modules/database"

  name             = "${var.environment}-db"
  subnet_ids       = module.network.private_subnet_ids
  instance_class   = local.cfg.db_class
  multi_az         = local.cfg.multi_az
  backup_retention = local.cfg.backup_days
  allowed_sg_id    = module.app.security_group_id
}

# ---------------------------------------------------------------------------
# Variables — environment identity comes from the caller (tfvars / -var).
# ---------------------------------------------------------------------------
variable "environment" {
  description = "Environment name: dev, staging, or prod."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "region" {
  description = "AWS region for this environment."
  type        = string
  default     = "ap-southeast-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the environment VPC (must not overlap across envs in a shared account)."
  type        = string
}

output "app_url" {
  description = "Load balancer DNS for this environment."
  value       = module.app.alb_dns_name
}
