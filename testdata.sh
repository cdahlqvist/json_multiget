curl -XPUT -H "Content-Type: application/json" -d '{"props":{"allow_mult":true}}' http://127.0.0.1:8098/buckets/person/props
curl -XDELETE http://127.0.0.1:8098/buckets/person/keys/stuart
curl -XDELETE http://127.0.0.1:8098/buckets/person/keys/bill
curl -XDELETE http://127.0.0.1:8098/buckets/person/keys/sarah
sleep 5
curl -XPUT -H 'Content-Type: application/json' -H 'Link: </buckets/person/keys/bill>; riaktag="friend"' -H 'Link: </buckets/person/keys/sarah>; riaktag="friend"' -H 'x-riak-meta-sex: male' -H 'x-riak-meta-added: 2013-11-15' -H 'x-riak-index-year_int: 1984' -H 'x-riak-index-name_bin: stuart, william, jones' -d '{"name":"Stuart William Jones","dob":"1984-05-23"}' http://127.0.0.1:8098/buckets/person/keys/stuart
curl -XPUT -H 'Content-Type: application/json' -H 'Link: </buckets/person/keys/stuart>; riaktag="friend"'  -H 'x-riak-meta-sex: male' -H 'x-riak-meta-added: 2013-11-15' -H 'x-riak-index-year_int: 1986' -H 'x-riak-index-name_bin: bill, anderson' -d '{"name":"Bill Anderson","dob":"1986-02-13"}' http://127.0.0.1:8098/buckets/person/keys/bill
curl -XPUT -H 'Content-Type: application/json' -H 'Link: </buckets/person/keys/stuart>; riaktag="friend"' -H 'x-riak-meta-sex: female' -H 'x-riak-meta-added: 2013-11-15' -H 'x-riak-index-year_int: 1987' -H 'x-riak-index-name_bin: sarah, bishop' -d '{"name":"Sarah Bishop","dob":"1987-11-01"}' http://127.0.0.1:8098/buckets/person/keys/sarah
curl -XDELETE http://127.0.0.1:8098/buckets/person/keys/sarah
curl -XPUT -H 'Content-Type: application/json' -H 'Link: </buckets/person/keys/stuart>; riaktag="friend"' -H 'x-riak-meta-sex: female' -H 'x-riak-meta-added: 2013-11-15' -H 'x-riak-index-year_int: 1987' -H 'x-riak-index-name_bin: sarah, barbara, bishop' -d '{"name":"Sarah Barbara Bishop","dob":"1987-11-01"}' http://127.0.0.1:8098/buckets/person/keys/sarah
