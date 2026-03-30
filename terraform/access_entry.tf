data "aws_caller_identity" "current" {}

resource "aws_eks_access_entry" "aws_eks_access_entry" {
  cluster_name  = aws_eks_cluster.dev-auto-cluster.name
  principal_arn = data.aws_caller_identity.current.arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "aws_eks_access_policy_association" {
  cluster_name  = aws_eks_cluster.dev-auto-cluster.name
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
  principal_arn = data.aws_caller_identity.current.arn

  access_scope {
    type = "cluster"
  }
}