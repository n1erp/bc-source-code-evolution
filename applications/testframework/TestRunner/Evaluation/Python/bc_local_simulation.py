# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

import csv

class LocalSimulation():
    def __init__(
            self,
            id,
            language_file):

        self.id = id
        self.data = []
        self.index = 0
        
        with open(language_file, encoding='utf-8', mode='r') as csvfile:
            reader = csv.reader(csvfile, delimiter=',', quotechar='"')
            next(reader)            
            for row in reader:
                if row[0] == "":
                    break
                self.data.append(row[0])
        
    def start(self):
        self.index = 0

    def stop(self):
        ...
        
    def put_response(self, message):
        print(f"\nResponse:\n   - '{message}'\n   - result: {self.index - 1}\n   - turn: 0\n")
    
    def peek_query(self):
        return self._get_at_index(self.index + 1)

    def get_query(self):
        query = self._get_at_index(self.index)
        print(f"\nQuery:\n   - '{query["query"][0:100]}'\n   - result: {self.index}\n   - turn: 0\n")

        self.index += 1

        return query
    
    def _get_at_index(self, index):
        return {
            "query": self.data[index],
            "messages": "",
            "conversation_turn_number": 0,
            "simulation_result_number": index,
        }
    
    def to_dict(self):
        return {
            "id": self.id,
            "scenario": self.scenario,
            "max_simulation_results": self.max_simulation_results,
            "max_conversation_turns": self.max_conversation_turns,
            "randomization_seed": self.randomization_seed
        }
