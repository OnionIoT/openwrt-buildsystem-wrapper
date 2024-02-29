project_name      = "openwrt-buildsystem-devops"
region            = "us-east-1"
deployment_bucket = "devops-openwrt-terraform-state-ezops-test-downloads"

repository = "OnionIoT/openwrt-buildsystem-wrapper"

stage_vars = {
  prod = {
    branch = "release"
  }
  dev = {
    branch = "devops"
  }
  devops = {
    branch = "devops"
  }
}
