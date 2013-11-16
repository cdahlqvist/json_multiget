curl -XPOST http://localhost:8098/mapred -H 'Content-Type: application/json' -d '{"inputs":"person","query":[{"map":{"language":"erlang","module":"json_multiget","function":"map_json_multiget"}}]}'
