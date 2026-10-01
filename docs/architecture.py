"""Architecture diagram for the README, rendered with mingrammer/diagrams.

Regenerate after changing the infrastructure:

    pip install diagrams      # also needs Graphviz (brew install graphviz / apt install graphviz)
    python docs/architecture.py
"""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.management import SystemsManager, SystemsManagerParameterStore
from diagrams.aws.network import (
    CloudFront,
    ElbApplicationLoadBalancer,
    Endpoint,
    InternetGateway,
    NATGateway,
)
from diagrams.onprem.client import User, Users
from diagrams.onprem.network import Internet, Nginx, Tomcat
from diagrams.programming.language import Java

OUTPUT = Path(__file__).with_name("architecture")

GRAPH = {
    "fontsize": "22",
    "fontname": "Helvetica",
    "pad": "0.4",
    "nodesep": "0.55",
    "ranksep": "0.9",
    "splines": "spline",
}
NODE = {"fontsize": "12", "fontname": "Helvetica"}
EDGE = {"fontsize": "11", "fontname": "Helvetica"}

# Edge styles: the request path vs. outbound traffic and operator access.
request = {"color": "#1f6feb", "penwidth": "2.2"}
outbound = {"color": "#6e7781", "style": "dashed"}
control = {"color": "#8250df", "style": "dotted", "penwidth": "1.5"}

# Layout is driven by edge direction (LR): each `>>` puts its target one column to the right.
# Everything the instance calls is written right-to-left with `<<`. NAT, the S3 endpoint and
# Parameter Store land in the ALB column, the IGW in the CloudFront column and the internet on the
# far left, so no line crosses the request path.
# The CI/CD pipeline has its own diagram in the README.
with Diagram(
    "Magnolia CMS on AWS: runtime",
    filename=str(OUTPUT),
    outformat="png",
    direction="LR",
    show=False,
    graph_attr=GRAPH,
    node_attr=NODE,
    edge_attr=EDGE,
):
    viewers = Users("Viewers")
    operator = User("Operator")
    nexus = Internet("Internet\n(Magnolia Nexus)")

    with Cluster("AWS · eu-west-1"):
        cdn = CloudFront("CloudFront\nTLS, HTTP→HTTPS\ncaches static UI assets\nadds secret origin header")
        ssm = SystemsManager("Session Manager")

        with Cluster("VPC 10.20.0.0/16"):
            igw = InternetGateway("Internet Gateway")

            with Cluster("Public subnets · eu-west-1a / 1b"):
                alb = ElbApplicationLoadBalancer("ALB\nCloudFront IPs only\n403 without header")
                nat = NATGateway("NAT Gateway")

            with Cluster("Private subnets · eu-west-1a / 1b"):
                with Cluster("EC2 m7i-flex.large · Amazon Linux 2023\nno public IP · no SSH · IMDSv2"):
                    nginx = Nginx("Nginx :80")
                    tomcat = Tomcat("Tomcat 10.1\nloopback :8080")
                    magnolia = Java("Magnolia CE 6.4\nauthor instance")
                    host = EC2("instance role\n(permissions boundary)")

            s3_endpoint = Endpoint("S3 gateway endpoint\n(dnf repositories)")

        params = SystemsManagerParameterStore("Parameter Store\nsuperuser password")

    # Request path
    viewers >> Edge(label="HTTPS", **request) >> cdn
    cdn >> Edge(label="HTTP + secret header", **request) >> alb
    alb >> Edge(label="health: /.rest/health/ready", **request) >> nginx
    nginx >> Edge(**request) >> tomcat >> Edge(**request) >> magnolia

    # Outbound from the private subnet (drawn right-to-left)
    nexus << Edge(label="WAR download", **outbound) << igw << Edge(**outbound) << nat << Edge(**outbound) << host
    s3_endpoint << Edge(label="packages", **outbound) << host
    params << Edge(label="first boot", **outbound) << host

    # Operator access, no SSH
    operator >> Edge(label="start-session", **control) >> ssm >> Edge(**control) >> host
