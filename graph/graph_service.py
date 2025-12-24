from flask import Flask, jsonify

app = Flask(__name__)

# Hardcoded graph data for the demo
# In a real app, you might add methods to add/remove nodes
graph_data = {
    "nodes": [
        {"id": 1, "label": "Start"},
        {"id": 2, "label": "Process A"},
        {"id": 3, "label": "Process B"},
        {"id": 4, "label": "End"}
    ],
    "edges": [
        {"from": 1, "to": 2},
        {"from": 1, "to": 3},
        {"from": 2, "to": 4},
        {"from": 3, "to": 4}
    ]
}

@app.route('/graph', methods=['GET'])
def get_graph():
    return jsonify(graph_data)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    # Listen on port 5003 as defined in your K8s service
    app.run(host='0.0.0.0', port=5003)