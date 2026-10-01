"""Shared look for the README diagrams, so every chart reads the same way."""

GRAPH = {
    "fontsize": "22",
    "fontname": "Helvetica",
    "pad": "0.7",
    "nodesep": "0.8",
    "ranksep": "1.6",
    # Right-angle edges. Ortho places edge labels poorly, so details live in node labels
    # and only a few short xlabels are used.
    "splines": "ortho",
}
NODE = {"fontsize": "12", "fontname": "Helvetica"}
EDGE = {"fontsize": "11", "fontname": "Helvetica"}

# Edge styles shared by all diagrams.
REQUEST = {"color": "#1f6feb", "penwidth": "2.2"}  # main flow
OUTBOUND = {"color": "#6e7781", "style": "dashed"}  # secondary / outbound traffic
CONTROL = {"color": "#8250df", "style": "dotted", "penwidth": "1.5"}  # access, credentials
