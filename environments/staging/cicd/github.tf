module "github_cicd" {
  source = "../../../modules/aws/github-cicd"

  repositories = [
    "ZingHall/*"
  ]
}
