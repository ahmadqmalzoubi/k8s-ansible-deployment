# Define required providers
terraform {
  required_version = ">= 0.14.0"
  required_providers {
    openstack = {
      source  = "terraform-provider-openstack/openstack"
      version = "~> 1.54.0"
    }
  }
}

# Configure the OpenStack Provider
provider "openstack" {
  # Using learning domain credentials for better isolation
  # These will be read from environment variables set by openrc file
  # Explicitly set insecure to bypass SSL certificate verification
  insecure    = true
  
  # Override to use public endpoint
  endpoint_type = "public"
}