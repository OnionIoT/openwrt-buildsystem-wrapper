
data "aws_caller_identity" "current" {}

locals {
  stage      = terraform.workspace
  stage_vars = var.stage_vars[local.stage]
  tags = {
    ProjectName = var.project_name
    Stage       = local.stage
    Scope       = "pipeline"
  }


  tf_codebuild_env_vars = {
    stage         = local.stage
    REGION        = var.region
    OUTPUT_BUCKET = var.deployment_bucket
  }

  codebuild_shared_secrets = {
  }
}

resource "aws_codestarconnections_connection" "github_connection" {
  name          = "${var.project_name}-git-${local.stage}"
  provider_type = "GitHub"
}


resource "aws_s3_bucket" "codepipeline_bucket" {
  bucket = "devops-${var.project_name}-artifacts-${local.stage}"
  tags   = local.tags
}

resource "aws_codepipeline" "codepipeline" {
  name     = "${var.project_name}-pipeline-${local.stage}"
  role_arn = aws_iam_role.codepipeline_role.arn
  tags     = local.tags

  artifact_store {
    location = aws_s3_bucket.codepipeline_bucket.bucket
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
        ConnectionArn        = aws_codestarconnections_connection.github_connection.arn
        FullRepositoryId     = var.repository
        BranchName           = local.stage_vars.branch
        DetectChanges        = true
        OutputArtifactFormat = "CODEBUILD_CLONE_REF"
      }
    }
  }

  stage {
    name = "Build"

    action {
      name = "Build"

      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      version          = "1"


      configuration = {
        ProjectName   = module.build_action.aws_codebuild_project
        PrimarySource = "source_output"
      }
    }
  }


}

