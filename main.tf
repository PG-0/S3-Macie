terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.16"
    }
  }

  required_version = ">= 1.2.0"
}

provider "aws" {
  region = "us-east-1"
}

# Variable for user input for email to be used for SNS set up. 
#   Also checks to see if an "@" exists as a simple form of validation

variable "user_email" {
  description = "Email address to be used as the endpoint for SNS"
  type = string

  validation {
    condition     = can(regex("@", var.user_email))
    error_message = "Email address must contain an @ symbol"
  }
}


### S3 Setup ###

# S3 - Generate Random Number for S3 bucket name

resource "random_integer" "Random-Number" {
  min = 100
  max = 999
}

# S3 - Create bucket with the random number in the title

resource "aws_s3_bucket" "S3-Macie-Bucket" {
  bucket = "s3-macie-bucket-${random_integer.Random-Number.result}"

  tags = {
    Terraform   = "True"
    Environment = "Dev"
  }
}

# S3 - Add Objects 

resource "aws_s3_object" "S3-Macie-Bucket-Objects" {
  for_each = fileset("${path.module}/S3_Files", "*")

  bucket = aws_s3_bucket.S3-Macie-Bucket.id
  key    = "${each.value}"
  source = "${path.module}/S3_Files/${each.value}"

}

### SNS Setup ### 

# SNS - Resource Policy random string generator for policy name

resource "random_string" "Policy-Name" {
  length = 8
  special = false
}

# Terraform attempts to grab AWS account ID (if authorized to do so)
#   Output will be printed in the terminal

data "aws_caller_identity" "current" {}


# SNS - Topic Creation

resource "aws_sns_topic" "S3-Macie-Notification" {
  name   = "s3-macie-sns-topic"

  policy = jsonencode({
    Version = "2008-10-17"
    Id      = "__default_policy_ID"
    Statement = [
      {
        Sid       = "__default_statement_ID"
        Effect    = "Allow"
        Principal = { AWS = "*" }
        Action    = [
          "SNS:Publish",
          "SNS:RemovePermission",
          "SNS:SetTopicAttributes",
          "SNS:DeleteTopic",
          "SNS:ListSubscriptionsByTopic",
          "SNS:GetTopicAttributes",
          "SNS:AddPermission",
          "SNS:Subscribe"
        ]
        # We use the output of the caller identity to grab the AWS account ID. 
        Resource  = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:s3-macie-sns-topic"
        Condition = {
          StringEquals = {
            "AWS:SourceOwner" = "${data.aws_caller_identity.current.account_id}"
          }
        }
      },
      {
        Sid       = "__console_pub_0"
        Effect    = "Allow"
        Principal = { AWS = ["${data.aws_caller_identity.current.account_id}"] }
        Action    = "SNS:Publish"
        Resource  = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:s3-macie-sns-topic"
      },
      {
        Sid       = "__console_sub_0"
        Effect    = "Allow"
        Principal = { AWS = ["${data.aws_caller_identity.current.account_id}"] }
        Action    = ["SNS:Subscribe"]
        Resource  = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:s3-macie-sns-topic"
      }
    ]
  })

  tags = {
    Terraform   = "True"
    Environment = "Dev"
  }
}

# SNS - Create Subscription. 

resource "aws_sns_topic_subscription" "User-Email-Target" {
  topic_arn = aws_sns_topic.S3-Macie-Notification.arn
  protocol  = "email"
  endpoint  = var.user_email
}

### EventBridge Setup ###

# Eventbridge - Rule Creation
resource "aws_cloudwatch_event_rule" "Macie-Events" {
  name        = "macie-events"

  event_pattern = jsonencode({
    detail-type = [
      {
        "source": ["aws.macie"],
        "detail-type": ["Macie Finding"]
      }
    ]
  })
}

# Eventbridge - Target set to Macie 
resource "aws_cloudwatch_event_target" "SNS-Target" {
  rule      = aws_cloudwatch_event_rule.Macie-Events.name
  arn       = aws_sns_topic.S3-Macie-Notification.arn
  # target_id = "sns-target" -- Not needed. Terraform should generate a unique one automatically
}

### Macie Setup ###

# Macie - Enable (Only use if the account has not yet enabled Macie)
#resource "aws_macie2_account" "Macie-For-S3" {}

# Macie - Job Setup
resource "aws_macie2_classification_job" "Macie-Job" {
  job_type = "ONE_TIME" # There are other options to set a schedule for scans. Via 'schedule_frequency'
  name     = "S3-PII-Analysis"
  s3_job_definition {
    bucket_definitions {
      account_id = "${data.aws_caller_identity.current.account_id}"
      buckets    = [aws_s3_bucket.S3-Macie-Bucket.id] #Could add more buckets here 
    }
  }
  #depends_on = [aws_macie2_account.Macie-For-S3]

  tags = {
    Terraform   = "True"
    Environment = "Dev"
  }
}

# Macie - Custom Data Identifier to check for Australian License Plates 

resource "aws_macie2_custom_data_identifier" "Data-Identifier-Australian-Plates" {
  name                   = "Austrailian_License_Plates"
  regex                  = "([0-9][a-zA-Z][a-zA-Z]-?[0-9][a-zA-Z][a-zA-Z])|([a-zA-Z][a-zA-Z][a-zA-Z]-?[0-9][0-9][0-9])|([a-zA-Z][a-zA-Z]-?[0-9][0-9]-?[a-zA-Z][a-zA-Z])|([0-9][0-9][0-9]-?[a-zA-Z][a-zA-Z][a-zA-Z])|([0-9][0-9][0-9]-?[0-9][a-zA-Z][a-zA-Z])"
  description            = "Checks for Australian license plates"

  #depends_on = [aws_macie2_account.Macie-For-S3]

  tags = {
    Terraform   = "True"
    Environment = "Dev"
  }
}

### Outputs ###

output "aws_acct_id" {
  value = data.aws_caller_identity.current.account_id
}

output "sns_topic" {
  value = aws_sns_topic.S3-Macie-Notification.name
}

output "email_input" {
  value = var.user_email
}