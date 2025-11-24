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
resource "aws_s3_bucket_lifecycle_configuration" "ci_artifacts_lifecycle" {
  bucket = aws_s3_bucket.ci_artifacts.id
  rule {
    id     = "expire-old-artifacts"
    status = "Enabled"
    expiration {
      days = 365
    }
    # If you have non-current versions due to versioning, you might also want to manage them:
    # noncurrent_version_expiration {
    #   noncurrent_days = 90
    # }
  }
}


# optional IAM user for CI (if not using OIDC)
# Given you are setting up OIDC for EKS, you should ideally use OIDC for your CI/CD as well,
# rather than a long-lived IAM user with access keys.
# I'm keeping this as-is, but note it's less secure than OIDC.
resource "aws_iam_user" "github_actions_user" {
  name = "${var.cluster_name}-gh-actions" # Changed var.cluster-name to var.cluster_name for consistency
  path = "/ci/"
}

resource "aws_iam_user_policy" "github_actions_s3" {
  name = "gh-actions-s3-upload"
  user = aws_iam_user.github_actions_user.name

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:PutObject",
          "s3:PutObjectAcl",
          "s3:GetObject",
          "s3:ListBucket",
          # For versioning, you might need additional permissions for listing/deleting specific versions
          "s3:ListBucketVersions",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ],
        Resource = [
          aws_s3_bucket.ci_artifacts.arn,
          "${aws_s3_bucket.ci_artifacts.arn}/*"
        ]
      }
    ]
  })
}

