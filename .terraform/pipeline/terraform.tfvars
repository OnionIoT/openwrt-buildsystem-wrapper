project_name      = "openwrt-buildsystem-devops"
region            = "us-east-1"
deployment_bucket = "downloads.onioniot.com"

repository = "OnionIoT/openwrt-buildsystem-wrapper"

stage_vars = {
  prod = {
    branch = "release"
  }
}
