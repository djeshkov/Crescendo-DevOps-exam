"""Architecture diagram for the README, rendered with mingrammer/diagrams.

Regenerate after changing the infrastructure:

    pip install diagrams      # also needs Graphviz (brew install graphviz / apt install graphviz)
    python docs/architecture.py
"""

from pathlib import Path

from diagrams import Cluster, Diagram, Edge
from diagrams.aws.compute import EC2
from diagrams.aws.management import SystemsManager, SystemsManagerParameterStore
from diagrams.aws.storage import SimpleStorageServiceS3Bucket
from diagrams.generic.blank import Blank
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

from _style import CONTROL as control
from _style import EDGE, GRAPH, NODE
from _style import OUTBOUND as outbound
from _style import REQUEST as request

OUTPUT = Path(__file__).with_name("architecture")

# Layout: the request path (blue) runs left to right. The instance's outbound traffic is written
# right-to-left with `<<`, so it never crosses the request path: AWS APIs without a VPC endpoint
# (Parameter Store, Session Manager) sit left, reached via NAT + IGW; S3 sits right, reached
# through its free gateway endpoint without touching NAT.
with Diagram(
    "Magnolia CMS on AWS",
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
    internet = Internet("Internet\n(Magnolia Nexus)")

    with Cluster("AWS · eu-west-1"):
        cdn = CloudFront(
            "CloudFront · HTTPS\n"
            "cached: /.resources/*, /VAADIN/*\n"
            "(origin Cache-Control, ?v= in key)\n"
            "not cached: pages, AdminCentral"
        )

        with Cluster("AWS APIs (reached via NAT)"):
            ssm = SystemsManager("Session Manager\n(no SSH)")
            params = SystemsManagerParameterStore("Parameter Store\nadmin password")

        s3 = SimpleStorageServiceS3Bucket("S3\n(OS packages)")

        with Cluster("VPC 10.20.0.0/16"):
            igw = InternetGateway("Internet Gateway")
            s3_endpoint = Endpoint("S3 gateway\nendpoint")

            with Cluster("eu-west-1b"):
                with Cluster("public 10.20.1.0/24"):
                    alb_b = ElbApplicationLoadBalancer("ALB node · 1b")
                with Cluster("private 10.20.11.0/24"):
                    spare = Blank("(reserved)")

            with Cluster("eu-west-1a"):
                with Cluster("public 10.20.0.0/24"):
                    alb = ElbApplicationLoadBalancer("ALB node · 1a\none ALB, CloudFront IPs only")
                    nat = NATGateway("NAT Gateway")

                with Cluster("private 10.20.10.0/24"):
                    with Cluster("EC2 instance · no public IP · no SSH"):
                        nginx = Nginx("Nginx")
                        tomcat = Tomcat("Tomcat")
                        magnolia = Java("Magnolia CE")
                        host = EC2("OS + SSM agent")

    # Request path
    viewers >> Edge(**request) >> cdn
    cdn >> Edge(**request) >> alb >> Edge(**request) >> nginx
    cdn >> Edge(**request) >> alb_b >> Edge(**request) >> nginx
    nginx >> Edge(**request) >> tomcat >> Edge(**request) >> magnolia

    # Outbound from the instance
    igw << Edge(**outbound) << nat << Edge(**outbound) << host
    internet << Edge(**outbound) << igw
    params << Edge(**outbound) << igw
    ssm << Edge(**outbound) << igw
    host >> Edge(**outbound) >> s3_endpoint >> Edge(**outbound) >> s3

    # Operator access: Session Manager relays over the channel the SSM agent keeps open
    operator >> Edge(**control) >> ssm

    # Layout only: keep the reserved subnet in the private column
    alb_b >> Edge(style="invis") >> spare
