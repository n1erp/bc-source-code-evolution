# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

from os import path
import sys

from flask import Flask, jsonify, request

import bc_simulation
import bc_local_simulation
import bc_evaluation
import bc_utils

azure_ai_project = bc_utils.get_azure_ai_project()
model_config = bc_utils.get_model_config()
simulations = {}
evaluations = {}
app = Flask(__name__)

### Evaluation API ###
@app.route('/evaluation', methods=['POST'])
def post_evaluation():
    data = request.get_json()
    
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    name = data.get("name")
    evaluators = data.get("evaluators")
    custom_evaluators = data.get("custom_evaluators")
    evaluation_data = data.get("evaluation_data")
    column_mapping = data.get("column_mapping")

    id = str(len(evaluations))
    evaluation = bc_evaluation.Evaluation(
        id,
        name,
        evaluators,
        custom_evaluators,
        evaluation_data,
        column_mapping,
        azure_ai_project,
        model_config)
    
    evaluations[evaluation.id] = evaluation

    print(f"Evaluation {evaluation.id} created with evaluators {evaluators}, custom_evaluators {custom_evaluators}, column_mapping {column_mapping}")
    
    evaluation.run_async() 
    return jsonify({ 'id': evaluation.id })

@app.route('/evaluation/<evaluation_id>', methods=['GET'])
def get_evaluation(evaluation_id):
    try:
        evaluation = evaluations[evaluation_id]
    except KeyError:
        return jsonify({}), 404

    return jsonify(evaluation.to_dict())

### Simulation API ###
@app.route('/simulation', methods=['POST'])
def post_simulation():
    data = request.get_json()

    language = data["locale"].split('-')[0] if "locale" in data else ""
    if language == "":
        language = "en"
    
    id = str(len(simulations))
    scenario = data["scenario"]
    max_simulation_results = data["max_simulation_results"]
    max_conversation_turns = data["max_conversation_turns"]
    randomization_seed = data["randomization_seed"]
    upia = data["upia"]

    language_file = bc_utils.sanitize_language_file(language)
    print(f"Sanitized language file path: {language_file}")
    if path.exists(language_file):
        print(f"Creating simulation with local dataset {language_file}.")
        simulation = bc_local_simulation.LocalSimulation(
            id,
            language_file
        )
    else:
        # File doesn't exist, use cloud simulation
        simulation = bc_simulation.Simulation(
            id,
            language,
            scenario,
            max_simulation_results,
            max_conversation_turns,
            randomization_seed,
            upia,
            azure_ai_project)
    
    simulations[simulation.id] = simulation

    print(f"Simulation {simulation.id} created with scenario {scenario}, max_simulation_results {max_simulation_results}, max_conversation_turns {max_conversation_turns}")

    simulation.start()

    return jsonify({ 'id': simulation.id })

@app.route('/simulation/<simulation_id>/queries', methods=['GET'])
def get_simulation_query(simulation_id):
    try:
        simulation = simulations[simulation_id]
    except KeyError:
        return jsonify({}), 404

    message = simulation.get_query()

    return jsonify(message)

@app.route('/simulation/<simulation_id>/queries/peek', methods=['GET'])
def peek_simulation_query(simulation_id):
    try:
        simulation = simulations[simulation_id]
    except KeyError:
        return jsonify({}), 404

    message = simulation.peek_query()
    
    return jsonify(message)

@app.route('/simulation/<simulation_id>/responses', methods=['PUT'])
def put_simulation_response(simulation_id):
    try:
        simulation = simulations[simulation_id]
    except KeyError:
        return jsonify({}), 404
    
    message = request.get_json()["response"]

    simulation.put_response(message)

    return jsonify({}), 200

@app.route('/simulation/<simulation_id>', methods=['GET'])
def get_simulation(simulation_id):
    try:
        simulation = simulations[simulation_id]
    except KeyError:
        return jsonify({}), 404

    return jsonify(simulation.to_dict())

@app.route('/simulation/<simulation_id>', methods=['DELETE'])
def delete_simulation(simulation_id):
    try:
        simulation = simulations[simulation_id]
    except KeyError:
        return jsonify({}), 404

    simulation.stop()
    del simulations[simulation_id]

    return jsonify({}), 200

if __name__ == '__main__':
    port = 8000
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    
    app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024 # 100 MB limit

    app.run(debug=True, port=port)
