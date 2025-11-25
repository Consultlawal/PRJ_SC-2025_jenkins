# infra-artifacts.tf

resource "random_id" "bucket_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "ci_artifacts" {
  bucket = "${var.cluster_name}-ci-artifacts-${random_id.bucket_suffix.hex}"

  # ACL is deprecated and should typically be replaced with S3 object ownership controls
  # and bucket policies for fine-grained permissions.
  # For now, if you need a similar effect, ensure your bucket policy aligns.
  # Removing `acl = "private"` is often necessary if you set `object_ownership = "BucketOwnerPreferred"`
  # or `BucketOwnerEnforced` in aws_s3_bucket_ownership_controls.
  # For simplicity and to avoid immediate errors, I'm removing it for now.
  # Consider adding `aws_s3_bucket_ownership_controls` and `aws_s3_bucket_public_access_block`
  # for production-grade S3 security.
}

# Use the dedicated resource for versioning
resource "aws_s3_bucket_versioning" "ci_artifacts_versioning" {
  bucket = aws_s3_bucket.ci_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Use the dedicated resource for lifecycle configuration
# infra-artifacts.tf
resource "aws_s3_bucket_lifecycle_configuration" "ci_artifacts_lifecycle" {
  bucket = aws_s3_bucket.ci_artifacts.id
  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"
    # Added filter block
    filter {} # This applies the rule to all objects in the bucket
    expiration {
      days = 365
    }
  }
}


# 