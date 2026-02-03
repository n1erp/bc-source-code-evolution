# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

from datetime import datetime
import tempfile
import json
import sys
import threading
import asyncio

import evaluators as bc_evaluators
import bc_utils

import azure.ai.evaluation as evaluation
from azure.ai.evaluation._evaluators._common import RaiServiceEvaluatorBase
from azure.identity import DefaultAzureCredential

class Evaluation():
    def __init__(self, id, name, evaluators, custom_evaluators, data, column_mapping, azure_ai_project, model_config):
        self.id = id
        self.name = name
        self.data = data
        self.column_mapping = column_mapping
        self.azure_ai_project = azure_ai_project
        self.model_config = model_config
        self.status = "Pending"
        self.result = None
        self.error = None
        self.thread = None
        self.evaluators = self._instantiate_evaluators(evaluators + custom_evaluators)

    def _instantiate_evaluators(self, evaluators):
        evaluator_instances = {}
        for evaluator in evaluators:
            if (hasattr(bc_evaluators, evaluator)):
                evaluator_class = getattr(bc_evaluators, evaluator)
                evaluator_instance = evaluator_class(self.model_config)
            else:
                evaluator_class = getattr(evaluation, evaluator)
                if issubclass(evaluator_class, RaiServiceEvaluatorBase):
                    evaluator_instance = evaluator_class(azure_ai_project=self.azure_ai_project, credential=DefaultAzureCredential())
                else:
                    evaluator_instance = evaluator_class(model_config=self.model_config)
            evaluator_instances[self._evaluator_to_key(evaluator)] = evaluator_instance
        return evaluator_instances

    def _evaluator_to_key(self, evaluator):
        '''Convert evalutor name to snake case key, e.g., "F1ScoreEvaluator" -> "f1_score"'''
        base_name = evaluator[:-len("Evaluator")]
        snake_case_name = ''.join(['_' + i.lower() if i.isupper() else i for i in base_name]).lstrip('_')
    
        return snake_case_name    

    def run(self):
        """Run the evaluation synchronously."""
        try:
            self.status = "Running"
            start_time = datetime.now()

            if isinstance(self.data, str):
                data_file = self.data
            else:
                with tempfile.NamedTemporaryFile(delete=False) as temp_file:
                    for line in self.data:
                        temp_file.write((json.dumps(line) + '\n').encode('utf-8'))
                    temp_file.flush()
                    data_file = temp_file.name

            evaluator_params = {
                "evaluation_name": self.name,
                "evaluators": self.evaluators,
                "data": data_file,
            }
            if self.column_mapping != None:
                evaluator_params["evaluator_config"] = {
                    "default": {
                        "column_mapping": json.loads(self.column_mapping)
                    }
                }

            result = evaluation.evaluate(
                **evaluator_params,
                azure_ai_project=self.azure_ai_project)

            result["evaluation"] = { 
                "name": self.name,
                "start_time": start_time,
                "end_time": datetime.now(),
                "data_file": data_file,
            }

            self.result = result
            self.status = "Success"
        except Exception as e:
            self.error = str(e)        
            self.status = "Failure"
            print(e)

    def run_async(self):
        """Run the evaluation asynchronously in a separate thread."""
        def async_runner():
            self.run()

        self.thread = threading.Thread(target=async_runner)
        self.thread.start()

    def to_dict(self):
        return {
            "id": self.id,
            "name": self.name,
            "status": self.status,
            "error": self.error,
            "result": self.result,
        }
    
if __name__ == "__main__":
    arguments = json.loads(sys.argv[1])
    name = arguments["name"]
    data  = arguments["data"]
    out_file = arguments["out_file"]

    evaluators = arguments.get("evaluators", [])
    custom_evaluators = arguments.get("custom_evaluators", [])
    column_mapping = arguments.get("column_mapping", None)

    azure_ai_project = bc_utils.get_azure_ai_project()
    model_config = bc_utils.get_model_config()
    
    evaluation_run = Evaluation(
        0,
        name,
        evaluators,
        custom_evaluators,
        data,
        column_mapping,
        azure_ai_project,
        model_config)

    evaluation_run.run()
    result = evaluation_run.result
    with open(out_file, 'w') as f:
        json.dump(result, f, default=bc_utils.handle_json_serialization)
