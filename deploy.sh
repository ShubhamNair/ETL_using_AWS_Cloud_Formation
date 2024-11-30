#!/bin/bash

# Variables
INPUT_BUCKET_NAME="s3lab4in-shubham121"
OUTPUT_BUCKET_NAME="s3lab4out-shubham"
REGION="us-east-1"
DATA_FOLDER="./data"
SCRIPT_FOLDER="./script"
STACK_NAME="lab5-stack10"

# Input files to upload
INPUT_FILES=(
  "${DATA_FOLDER}/in_iris_json.json"
  "${DATA_FOLDER}/yellow_tripdata_2024_01_parquet.parquet"
  "${DATA_FOLDER}/california_housing_avro.avro"
  "${DATA_FOLDER}/titanic_csv.csv"
)

# S3 paths for input files
S3_PATHS=(
  "s3://${INPUT_BUCKET_NAME}/in_iris_json.json"
  "s3://${INPUT_BUCKET_NAME}/yellow_tripdata_2024_01_parquet.parquet"
  "s3://${INPUT_BUCKET_NAME}/california_housing_avro.avro"
  "s3://${INPUT_BUCKET_NAME}/titanic_csv.csv"
)

# Check and create buckets if necessary
echo "Checking and creating buckets if necessary..."
for BUCKET in "$INPUT_BUCKET_NAME" "$OUTPUT_BUCKET_NAME"; do
  if aws s3api head-bucket --bucket "$BUCKET" --region "$REGION" 2>/dev/null; then
    echo "Bucket $BUCKET already exists."
  else
    echo "Bucket $BUCKET does not exist. Creating..."
    if [ "$REGION" == "us-east-1" ]; then
      aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
    else
      aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
        --create-bucket-configuration LocationConstraint="$REGION"
    fi
    if [ $? -eq 0 ]; then
      echo "Bucket $BUCKET created successfully."
    else
      echo "Failed to create bucket $BUCKET. Exiting."
      exit 1
    fi
  fi
done

# Upload Glue scripts to S3
echo "Uploading Glue scripts to S3..."
if aws s3 cp "$SCRIPT_FOLDER/" "s3://${INPUT_BUCKET_NAME}/scripts/" --recursive --region "$REGION"; then
  echo "Glue scripts uploaded successfully."
else
  echo "Failed to upload Glue scripts. Exiting."
  exit 1
fi

# Upload input files to S3
echo "Uploading input files to S3..."
for i in "${!INPUT_FILES[@]}"; do
  local_file="${INPUT_FILES[$i]}"
  s3_path="${S3_PATHS[$i]}"
  echo "Uploading ${local_file} to ${s3_path}..."
  if ! aws s3 cp "$local_file" "$s3_path" --region "$REGION"; then
    echo "Failed to upload $local_file. Exiting."
    exit 1
  fi
done

# Verify if all files are uploaded
echo "Verifying S3 uploads..."
for s3_path in "${S3_PATHS[@]}"; do
  if ! aws s3 ls "$s3_path" > /dev/null 2>&1; then
    echo "Error: File $s3_path not found in S3. Exiting."
    exit 1
  fi
done
echo "All files uploaded successfully!"

# Deploy the CloudFormation stack
echo "Deploying CloudFormation stack: $STACK_NAME"
if aws cloudformation deploy \
  --stack-name "$STACK_NAME" \
  --template-file ./template.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$REGION"; then
  echo "CloudFormation stack deployed successfully."
else
  echo "Failed to deploy CloudFormation stack. Exiting."
  exit 1
fi

# Wait for stack to complete
echo "Waiting for CloudFormation stack creation..."
if aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME"; then
  echo "CloudFormation stack creation completed successfully."
else
  echo "CloudFormation stack creation failed. Exiting."
  exit 1
fi

# Start the Glue Crawler
echo "Starting Glue Crawler..."
if aws glue start-crawler --name lab4db-crawler; then
  echo "Glue Crawler started successfully."
else
  echo "Failed to start Glue Crawler. Exiting."
  exit 1
fi

# Wait for the crawler to complete
echo "Waiting for Glue Crawler to complete..."
while true; do
  CRAWLER_STATE=$(aws glue get-crawler --name lab4db-crawler --query 'Crawler.State' --output text)
  if [[ "$CRAWLER_STATE" == "READY" ]]; then
    echo "Glue Crawler completed successfully!"
    break
  fi
  echo "Waiting for Glue Crawler..."
  sleep 10
done

# Start the Glue Workflow
echo "Starting Glue Workflow..."
WORKFLOW_RUN_ID=$(aws glue start-workflow-run --name lab4-workflow --query 'RunId' --output text)
if [[ -n "$WORKFLOW_RUN_ID" ]]; then
  echo "Glue Workflow started with RunId: $WORKFLOW_RUN_ID"
else
  echo "Failed to start Glue Workflow. Exiting."
  exit 1
fi

echo "Deployment completed successfully!"
