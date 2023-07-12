variable "project_name" {
  description = "The name of the project"
  default     = "annoying-cicd"
}

provider "aws" {
  region = "eu-north-1"
}

resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "${var.project_name}-perkele"
  force_destroy = true
}

resource "aws_iam_role" "codebuild_role" {
  name = "${var.project_name}-codebuild-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect  = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_codebuild_project" "code_build" {
  name          = "${var.project_name}-codebuild-project"
  description   = "Example CodeBuild project"
  service_role  = aws_iam_role.codebuild_role.arn
  build_timeout = "5"
  
  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/ubuntu-base:14.04"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
  }

  source {
    type            = "CODEPIPELINE"
    buildspec       = "buildspec.yml"
    report_build_status = true
  }
}

resource "aws_codepipeline" "codepipeline" {
  name     = "${var.project_name}-codepipeline"
  role_arn = aws_iam_role.codepipeline_role.arn
  
  artifact_store {
    location = aws_s3_bucket.artifact_bucket.bucket
    type     = "S3"
  }
  
  stage {
    name = "Source"
    
    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_output"]
      
      configuration = {
        ConnectionArn = var.codestar_arn
        FullRepositoryId = "jojopojo/codebuild-test2"
        BranchName = "main"
      }
    }
  }
  
  stage {
    name = "Build"
    
    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"
      
      configuration = {
        ProjectName = aws_codebuild_project.code_build.name
      }
    }
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name = "${var.project_name}-codepipeline-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect  = "Allow"
        Principal = {
          Service = "codepipeline.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_codestarconnections_connection" "connection" {
  provider_type = "GitHub"
  name          = "${var.project_name}-github-connection"
}


resource "aws_iam_policy" "codebuild_policy" {
  name = "${var.project_name}-codebuild-policy"
  path = "/"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Resource = "arn:aws:logs:*:*:*",
        Effect   = "Allow"
      },
      {
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:ListBucket"
        ],
        Resource = [
          "${aws_s3_bucket.artifact_bucket.arn}",
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ],
        Effect = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_policy_attachment" {
  role       = aws_iam_role.codebuild_role.name
  policy_arn = aws_iam_policy.codebuild_policy.arn
}
resource "aws_iam_policy" "codepipeline_policy" {
  name = "${var.project_name}-codepipeline-policy"
  path = "/"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "codebuild:BatchGetBuilds",
          "codebuild:StartBuild"
        ],
        Resource = "${aws_codebuild_project.code_build.arn}",
        Effect   = "Allow"
      },
      {
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject"
        ],
        Resource = [
          "${aws_s3_bucket.artifact_bucket.arn}",
          "${aws_s3_bucket.artifact_bucket.arn}/*"
        ],
        Effect = "Allow"
      },
      {
        Action = [
            "codestar-connections:UseConnection"
        ],
        Resource = [
            "${var.codestar_arn}",
            "${var.codestar_arn}/*"
        ],
        Effect = "Allow"
      },
      {
        Action = [
          "iam:PassRole"
        ],
        Resource = "${aws_iam_role.codebuild_role.arn}",
        Effect   = "Allow"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codepipeline_policy_attachment" {
  role       = aws_iam_role.codepipeline_role.name
  policy_arn = aws_iam_policy.codepipeline_policy.arn
}