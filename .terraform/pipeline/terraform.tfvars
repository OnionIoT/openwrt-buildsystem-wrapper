project_name      = "openwrt-buildsystem"
region            = "us-east-1"
deployment_bucket = "downloads.onioniot.com"
repository        = "OnionIoT/openwrt-buildsystem-wrapper"

# Set the buildspec file name. Options include 'development-buildspec.yml' for development or 'buildspec.yml' for production.
buildspec_file_name = "buildspec.yml"

stage_vars = {
  prod = {
    branch = "release"
  }
}
