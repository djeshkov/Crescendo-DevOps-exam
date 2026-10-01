"""CI/CD diagram for the README, rendered with mingrammer/diagrams.

Regenerate after changing the workflow:

    pip install diagrams      # also needs Graphviz
    python docs/cicd.py
"""

from pathlib import Path

from _style import CONTROL as control
from _style import EDGE, GRAPH, NODE
from _style import OUTBOUND as outbound
from _style import REQUEST as request
from diagrams import Cluster, Diagram, Edge
from diagrams.aws.general import General
from diagrams.aws.security import IAMRole
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.onprem.client import User
from diagrams.onprem.iac import Terraform
from diagrams.onprem.vcs import Github
from diagrams.programming.flowchart import Decision

OUTPUT = Path(__file__).with_name("cicd")

# Two lanes, both left to right: what runs on a pull request and what runs on main.
# Every job reaches AWS only through GitHub OIDC; no AWS keys are stored in GitHub.
with Diagram(
    "Magnolia CMS on AWS: CI/CD",
    filename=str(OUTPUT),
    outformat="png",
    direction="LR",
    show=False,
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    with Cluster("GitHub Actions · .github/workflows/terraform.yml"):
        with Cluster("Push to main (after merge)"):
            merge = Github("merge to main")
            main_checks = Terraform("fmt · validate · tflint")
            main_plan = Terraform("plan\n+ fingerprint")
            approve = User("approval\naws-dev environment")
            same = Decision("re-plan:\nsame fingerprint?")
            apply = Terraform("apply")

        with Cluster("Pull request"):
            pr = Github("pull request")
            pr_checks = Terraform("fmt · validate · tflint\nboth stacks, no AWS access")
            pr_plan = Terraform("plan")
            pr_comment = Github("plan posted\nas PR comment")

    with Cluster("AWS account"):
        with Cluster("bootstrap/ (applied once, by a human)"):
            plan_role = IAMRole("plan role\nReadOnlyAccess + lock file\nPRs and main only")
            apply_role = IAMRole("apply role\nPowerUser + fenced IAM\naws-dev environment only")
            state = SimpleStorageServiceS3Bucket("Terraform state\nversioned · encrypted")
        with Cluster("terraform/ (applied by CI)"):
            stack = General("Magnolia stack\nVPC · EC2 · ALB · CloudFront")

    # Pull request lane
    pr >> Edge(**request) >> pr_checks >> Edge(**request) >> pr_plan >> Edge(**request) >> pr_comment

    # main lane: nothing is applied without a human approval and an unchanged plan
    merge >> Edge(**request) >> main_checks >> Edge(**request) >> main_plan >> Edge(**request) >> approve
    approve >> Edge(**request) >> same >> Edge(xlabel="yes", **request) >> apply

    # Credentials: OIDC tokens exchanged for short-lived role sessions
    pr_plan >> Edge(xlabel="OIDC", **control) >> plan_role
    main_plan >> Edge(xlabel="OIDC", **control) >> plan_role
    apply >> Edge(xlabel="OIDC", **control) >> apply_role

    # What the roles touch
    plan_role >> Edge(**outbound) >> state
    apply_role >> Edge(**outbound) >> state
    apply_role >> Edge(**request) >> stack
