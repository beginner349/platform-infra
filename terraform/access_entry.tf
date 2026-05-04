# There is a CI/CD variable named TF_VAR_AWS_ROLE_NAME, it has a TF_VAR_ prefix and terraform will automatically inject its value into this variable
variable "AWS_ROLE_NAME" {
  type        = string
  description = "Automatically populated by GitHub's TF_VAR_AWS_ROLE_NAME"
}

data "aws_iam_role" "github_oidc_role" {
  name = var.AWS_ROLE_NAME
}

resource "aws_eks_access_entry" "aws_eks_access_entry" {
  cluster_name  = aws_eks_cluster.my-eks-cluster.name
  principal_arn = data.aws_iam_role.github_oidc_role.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "aws_eks_access_policy_association" {
  cluster_name  = aws_eks_cluster.my-eks-cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_iam_role.github_oidc_role.arn

  access_scope {
    type = "cluster"
  }
}
