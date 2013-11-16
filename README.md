#json_multiget

##Overview
This is an experimental implementation of multiget for Riak via MapReduce. At the moment it encodes all results in JSON, and is therefore limited to fetching objects that are correctly encoded in JSON.

The MapReduce library `json_multiget` contains two Erlang MapReduce functions, `map_json_multiget` and `reduce_json_multiget`. 

The Map phase function `map_json_multiget` will encode any object passed into it that have a valid JSON value and return an error encoded in JSON if the object could not be found or was not recognized as valid JSON. This function will follow the normal MapReduce limitations in that it does not perform a quorum read and do not cause read-repair to occur. Results can however be streamed back to the client which makes it quite efficient.

The reduce phase function `reduce_json_multiget` on the other hand will take a list of keys to retrieve as an argument and will manage concurrent retrieval using the internal Riak client. Normal consistency parameters like `R` and `PR` can be supplied as part of the configuration and this function will perform a quorum read that will trigger read repair. This reduce phase function will perform the retrieval of all configured keys in one go, and should therefore only be triggered once.

##Installation
Check out and compile the module as shown below.

```
$> git clone git@github.com:cdahlqvist/json_multiget.git
$> cd json_multiget
$> erlc json_multiget.erl
```

The compiled file must then be deployed to all nodes in the cluster. This is done by placing the `json_mapreduce.beam` file in a directory indicated by the `add_paths` parameter in the riak_kv section of the app.config file. Please see the [Basho Docs](http://docs.basho.com/riak/latest/ops/advanced/install-custom-code/) for further details.

##Test Data

The file `testdata.sh` contains curl commands to create three test records with a variety of features used in order to show all types of encodings. One of these contain siblings, out of which one is a tombstone. This test data has been used in all examples below.

##map_json_multiget
The `map_json_multiget` function takes no arguments and can be in any mapReduce job to return JSON encoded objects. The example below show how a mapreduce job can be created to return all records in the `person` bucket.

```
curl -XPOST http://localhost:8098/mapred 
    -H 'Content-Type: application/json' 
    -d '{
            "inputs":"person",
            "query":[
                {
                    "map":{"language":"erlang",
                        "module":"json_multiget",
                        "function":"map_json_multiget"
                    }
                }
            ]
        }'
```

##reduce_json_multiget
The `reduce_json_multiget` function takes a JSON document as argument. A single bucket/key pair should be sent in to ensure that the reduce phase function is only run twice. As the input is ignored, the bucket/key pair passed in does not need to exist.

The level of concurrency can be controlled through two parameters that can be specified under the `riak_kv` section in the `app.config` file. There are:

**default_multiget_concurrency** - This is the concurrency level that will be used by default. Default value is 10.

**max_multiget_concurrency** - This is the maximum concurrency level that may be used. Default value is 20.

An example of how to run a MapReduce job that returns a some records from the `person` bucket is shown below:

```
curl -XPOST http://localhost:8098/mapred 
    -H 'Content-Type: application/json' 
    -d '{
            "inputs":[["notfound","notfound"]],
            "query":[
                {
                    "reduce":{
                        "language":"erlang",
                        "module":"json_multiget",
                        "function":"reduce_json_multiget",
                        "arg":"{
                            \"bucket\":\"person\",
                            \"keylist\":[\"bill\",\"sarah\",\"bob\",\"stuart\"],
                            \"timeout\":60000,
                            \"concurrency\":5,
                            \"r\":2,
                            \"pr\":0
                        }"
                    }
                }
            ]
        }'

```

The JSON argument can contain the following fields:

**bucket** - The name of the bucket to retrieve values from. All retrieved keys must belong to this bucket. [mandatory]

**keylist** - List of the keys to retrieve. [Mandatory]

**timeout** - Request timeout for each GET request expressed in milliseconds. Default is 60000. [Optional]

**concurrency** - Specifies the maximum number of concurrent processes to use when fetching the objects. This must not be greater than the value of the `max_multiget_concurrency` parameter described above. [Optional]

**r** - Specifies the `R` value to use. [Optional]

**pr** - Specifies the `PR` value to use. [Optional]

##Result Encoding
The below example shows how Riak Objects returned by these functions are encoded. One of the objects contsins siblings, out of which one is a tombstone. The example also contains one requested key that could not be found and therefore returned an error.


```
[
"{
    \"bucket\":\"person\",
    \"key\":\"sarah\",
    \"vclock\":\"a85hYGBgzGDKBVIcypz/fgZZpqZkMCUy57EyrDj8+zRfFgA=\",
    \"contents\":[
        {
            \"value\":{
                \"name\":\"Sarah Barbara Bishop\",
                \"dob\":\"1987-11-01\"
            },
            \"usermeta\":{
                \"X-Riak-Meta-Added\":\"2013-11-15\",
                \"X-Riak-Meta-Sex\":\"female\"
            },
            \"last-modified\":\"2013-11-16 10:23:36 GMT\",
            \"indexes\":{
                \"name_bin\":[\"sarah\",\"bishop\",\"barbara\"],
                \"year_int\":[1987]
            },
            \"content-type\":\"application/json\",
            \"vtag\":\"3nTF5sqx2ZJoMWmdEVGmZe\",
            \"links\":[
                {
                    \"bucket\":\"person\",
                    \"key\":\"stuart\",
                    \"tag\":\"friend\"
                }
            ]
        },
        {
            \"last-modified\":\"2013-11-16 10:23:36 GMT\",
            \"deleted\":\"true\",
            \"vtag\":\"68hD5xRoNMypXcQ4Udw1jA\"
        }
    ]
}",
"{
    \"bucket\":\"person\",
    \"key\":\"bill\",
    \"vclock\":\"a85hYGBgzGDKBVIcypz/fgZZpiZmMCUy5rEyrDj8+zRfFgA=\",
    \"contents\":[
        {
            \"value\":{
                \"name\":\"Bill Anderson\",
                \"dob\":\"1986-02-13\"
            },
            \"usermeta\":{
                \"X-Riak-Meta-Added\":\"2013-11-15\",
                \"X-Riak-Meta-Sex\":\"male\"
            },
            \"last-modified\":\"2013-11-16 10:23:36 GMT\",
            \"indexes\":{
                \"name_bin\":[\"bill\",\"anderson\"],
                \"year_int\":[1986]
            },
            \"content-type\":\"application/json\",
            \"vtag\":\"48BN2NJ5HOftBwOLWecb1K\",
            \"links\":[
                {
                    \"bucket\":\"person\",
                    \"key\":\"stuart\",
                    \"tag\":\"friend\"
                }
            ]
        }
    ]
}",
"{
    \"bucket\":\"person\",
    \"key\":\"stuart\",
    \"vclock\":\"a85hYGBgzGDKBVIcypz/fgZZpiZmMCUy5rEyrDj8+zRfFgA=\",
    \"contents\":[
        {
            \"value\":{
                \"name\":\"Stuart William Jones\",
                \"dob\":\"1984-05-23\"
            },
            \"usermeta\":{
                \"X-Riak-Meta-Added\":\"2013-11-15\",
                \"X-Riak-Meta-Sex\":\"male\"
            },
            \"last-modified\":\"2013-11-16 10:23:36 GMT\",
            \"indexes\":{
                \"name_bin\":[\"william\",\"stuart\",\"jones\"],
                \"year_int\":[1984]
            },
            \"content-type\":\"application/json\",
            \"vtag\":\"6NonPuNWuYSO4TyumUKAkA\",
            \"links\":[
                {
                    \"bucket\":\"person\",
                    \"key\":\"bill\",
                    \"tag\":\"friend\"
                },
                {
                    \"bucket\":\"person\",
                    \"key\":\"sarah\",
                    \"tag\":\"friend\"
                }
            ]
        }
    ]
}",
"{
    \"bucket\":\"person\",
    \"key\":\"bob\",
    \"error\":\"notfound\"
}"
]
```