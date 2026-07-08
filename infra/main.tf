terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
  }

  backend "s3" {
    bucket         = "dram-soc-tfstate"
    key            = "showcase.dram-soc.org/terraform.tfstate"
    region         = "us-west-2"
    encrypt        = true
    dynamodb_table = "dram-soc-tfstate-lock"
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      Project     = "showcase.dram-soc.org"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = var.owner_email
    }
  }
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
  default_tags {
    tags = {
      Project     = "showcase.dram-soc.org"
      Environment = "prod"
      ManagedBy   = "terraform"
      Owner       = var.owner_email
    }
  }
}
