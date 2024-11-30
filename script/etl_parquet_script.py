import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.dynamicframe import DynamicFrame
from pyspark.sql import functions as SqlFuncs

# Helper function for aggregations
def sparkAggregate(glueContext, parentFrame, groups, aggs, transformation_ctx) -> DynamicFrame:
    aggsFuncs = []
    for column, func in aggs:
        aggsFuncs.append(getattr(SqlFuncs, func)(column))
    result = parentFrame.toDF().groupBy(*groups).agg(*aggsFuncs) if len(groups) > 0 else parentFrame.toDF().agg(*aggsFuncs)
    return DynamicFrame.fromDF(result, glueContext, transformation_ctx)

# Retrieve job parameters
args = getResolvedOptions(sys.argv, ['JOB_NAME', 'DATABASE_NAME', 'INPUT_TABLE_NAME', 'OUTPUT_S3_PATH', 'OUTPUT_TABLE_NAME'])
database_name = args['DATABASE_NAME']
input_table_name = args['INPUT_TABLE_NAME']
output_s3_path = args['OUTPUT_S3_PATH']
output_table_name = args['OUTPUT_TABLE_NAME']

# Initialize Glue job context
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Load data from the Glue Data Catalog
input_dynamic_frame = glueContext.create_dynamic_frame.from_catalog(
    database=database_name, 
    table_name=input_table_name, 
    transformation_ctx="input_dynamic_frame"
)

# Perform aggregations
aggregated_frame = sparkAggregate(
    glueContext,
    parentFrame=input_dynamic_frame,
    groups=[],
    aggs=[
        ["total_amount", "max"],
        ["passenger_count", "max"],
        ["tip_amount", "max"],
        ["payment_type", "countDistinct"]
    ],
    transformation_ctx="aggregated_frame"
)

# Write the output to S3 and update the Glue Catalog
output_sink = glueContext.getSink(
    path=output_s3_path,
    connection_type="s3",
    updateBehavior="UPDATE_IN_DATABASE",
    partitionKeys=[],
    enableUpdateCatalog=True,
    transformation_ctx="output_sink"
)
output_sink.setCatalogInfo(catalogDatabase=database_name, catalogTableName=output_table_name)
output_sink.setFormat("glueparquet", compression="snappy")
output_sink.writeFrame(aggregated_frame)

# Commit the Glue job
job.commit()
