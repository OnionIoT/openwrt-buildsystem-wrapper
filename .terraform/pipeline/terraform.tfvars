project_name      = "openwrt-buildsystem"
region            = "us-east-1"
deployment_bucket = "devops-openwrt-terraform-state-ezops-test-downloads"

repository = "OnionIoT/openwrt-buildsystem-wrapper"

stage_vars = {
  prod = {
    branch = "release"
  }
  devops = {
    branch = "devops-28.03"
  }
  dev = {
    branch = "devops-28.03"
  }
}
