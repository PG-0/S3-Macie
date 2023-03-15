# S3-Macie Mini Project

Mini Project that utilizes multiple AWS services. Macie will scan for PII and send an alert

The project is based on Adrian Cantrill's mini project which can be found here: https://github.com/acantril/learn-cantrill-io-labs/blob/master/00-aws-simple-demos/aws-macie/Readme.md

I will add my own spin to this by creating the infrastructure via Terraform. The infrastructure will be provisioned but the macie job will not be executed. You can run the job within the AWS console and Macie will scan the bucket for PII content and produce a report. 

AWS infra components used in the Project: Macie, S3, SNS, EventBridge
* Macie - AWS AI offering that scans for sensitive information
* S3 - Object Storage in AWS
* SNS - Notificaiton service. Email is used for this project
* Eventbridge - AWS service that triggers an alert once a Macie Job is run 

Note: If Macie is not enabled in the account, you will need to uncomment the section in the terraform script " resource "aws_macie2_account" "Macie-For-S3" {}. You will need to uncomment "depends_on = [aws_macie2_account.Macie-For-S3]" under the Macie Section as well. 
