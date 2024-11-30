#!/bin/bash

# Variables
STACK_NAME="lab5-stack10"
INPUT_BUCKET_NAME="s3lab4in-shubham121"
OUTPUT_BUCKET_NAME="s3lab4out-shubham"
REGION="us-east-1"
GLUE_DATABASE="s3lab4in-shubham121"
WORKFLOW_NAME="lab4-workflow"

echo "Starting destruction process for CloudFormation stack: $STACK_NAME"

# Delete the CloudFormation stack
echo "Deleting CloudFormation stack: $STACK_NAME"
aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION

# Wait for the stack to be deleted
echo "Waiting for CloudFormation stack deletion to complete..."
aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION

if [ $? -eq 0 ]; then
  echo "CloudFormation stack $STACK_NAME deleted successfully!"
else
  echo "Failed to delete CloudFormation stack $STACK_NAME. Exiting."
  exit 1
fi

# Delete Glue Workflow
echo "Deleting Glue Workflow: $WORKFLOW_NAME"
aws glue delete-workflow --name $WORKFLOW_NAME --region $REGION 2>/dev/null
if [ $? -eq 0 ]; then
  echo "Glue Workflow $WORKFLOW_NAME deleted successfully!"
else
  echo "Glue Workflow $WORKFLOW_NAME does not exist or failed to delete."
fi

# Delete Glue jobs explicitly if required
echo "Deleting Glue jobs..."
GLUE_JOBS=("etl-job-json" "etl-job-parquet" "etl-job-avro" "etl-job-csv")
for JOB in "${GLUE_JOBS[@]}"; do
  echo "Deleting Glue job: $JOB"
  aws glue delete-job --job-name $JOB --region $REGION 2>/dev/null
done
echo "Glue jobs deleted successfully!"

# Delete Glue Crawler
CRAWLER_NAME="lab4db-crawler"
echo "Deleting Glue Crawler: $CRAWLER_NAME"
aws glue delete-crawler --name $CRAWLER_NAME --region $REGION 2>/dev/null
if [ $? -eq 0 ]; then
  echo "Glue Crawler $CRAWLER_NAME deleted successfully!"
else
  echo "Glue Crawler $CRAWLER_NAME does not exist or failed to delete."
fi

# Delete Glue Database
echo "Deleting Glue Database: $GLUE_DATABASE"
aws glue delete-database --name $GLUE_DATABASE --region $REGION 2>/dev/null
if [ $? -eq 0 ]; then
  echo "Glue Database $GLUE_DATABASE deleted successfully!"
else
  echo "Glue Database $GLUE_DATABASE does not exist or failed to delete."
fi

# Empty the S3 buckets
echo "Emptying S3 buckets..."
BUCKETS=($INPUT_BUCKET_NAME $OUTPUT_BUCKET_NAME)
for BUCKET in "${BUCKETS[@]}"; do
  echo "Deleting all objects in $BUCKET..."
  aws s3 rm "s3://$BUCKET/" --recursive --region $REGION
done

# Delete the S3 buckets
echo "Deleting S3 buckets..."
for BUCKET in "${BUCKETS[@]}"; do
  echo "Deleting bucket: $BUCKET"
  aws s3api delete-bucket --bucket $BUCKET --region $REGION
done

echo "All resources deleted successfully!"
