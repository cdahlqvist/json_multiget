curl -XPOST http://localhost:8098/mapred -H 'Content-Type: application/json' -d '{"inputs":"person","query":[{"map":{"language":"erlang","module":"json_multiget","function":"map_json_multiget"}}]}'

curl -XPOST http://localhost:8098/mapred -H 'Content-Type: application/json' -d '{"inputs":[["notfound","notfound"]],"query":[{"reduce":{"language":"erlang","module":"json_multiget","function":"reduce_json_multiget","arg":"{\"bucket\":\"person\",\"keylist\":[\"bill\",\"sarah\",\"bob\"],\"timeout\":60000,\"concurrency\":5,\"r\":2,\"pr\":0}"}}]}'


