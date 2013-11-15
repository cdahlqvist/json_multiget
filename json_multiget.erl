-module(json_multiget).

-behaviour(gen_server).

%% Export mapreduce function
-export([map_json_multiget/3,
         reduce_json_multiget/2]).

%% Application callbacks
-export([start/0,
         multiget/6,
         get_object/4]).

-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(DEFAULT_TIMEOUT, 60000).

-define(ALLOWED_CONTENT_TYPES, ["application/json","application/x-javascript","text/javascript","text/x-javascript","text/x-json"]).

-record(state, {from, bucket, keylist, workerlist, options, results}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% External Functions                          %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% @spec map_json_multiget(riak_object:riak_object(), term(), term()) ->
%%                   [{bucket(), key(), binary(), contents()} | {error, notfound}]
%% @doc map phase function returning JSON encoded objecxt
map_json_multiget({error, notfound}, _, _) ->
    [json_encode_error(notfound)];
map_json_multiget(RO, _, _) ->
    [json_encode_object(RO)].

%% @spec reduce_json_multiget(any(), term()) ->
%%                   [binary()]
%% @doc reduce phase function for parallel multiget
reduce_json_multiget(Val, Arg) when is_binary(Arg) ->
    {struct, Props} = mochijson2:decode(Arg),
    reduce_json_multiget(Val, Props);
reduce_json_multiget(_, Props) ->
    Concurrency = determine_concurrency(Props),
    Options = case {proplists:lookup(<<"pr">>, Props), proplists:lookup(<<"r">>, Props)} of
        {none, none} ->
            [];
        {none, R} when is_integer(R) ->
            [{r, R}];
        {PR, _} when is_integer(PR) ->
            [{pr, PR}];
        {none, Rbin} when is_binary(Rbin) ->
            [{r, list_to_atom(string:to_lower(binary_to_list(Rbin)))}];
        {PRbin, _} when is_binary(PRbin) ->
            [{pr, list_to_atom(string:to_lower(binary_to_list(PRbin)))}];
        _ ->
            []
    end,
    Timeout = case proplists:lookup(<<"timeout">>, Props) of
        none ->
            ?DEFAULT_TIMEOUT;
        {_, T} when is_integer(T) andalso T > 0 ->
            T;
        _ ->
            ?DEFAULT_TIMEOUT
    end,  
    case {proplists:lookup(<<"bucket">>, Props), proplists:lookup(<<"keylist">>, Props)} of
        {_,{_, []}} ->
            [{error, missing_keylist}];
        {{_, Bucket},{_, KeyList}} when is_list(KeyList) andalso is_binary(Bucket) ->
            case ?MODULE:start() of
                {ok, Pid} ->
                    multiget(Pid, Bucket, KeyList, Concurrency, Options, Timeout);
                {error, _} ->
                    [json_encode_error(processing_error)]
            end;
        {{_, _},none} ->
            [json_encode_error(missing_keylist)];
        {none,{_, _}} ->
            [json_encode_error(missing_bucket)];
        {none,none} ->
            [json_encode_error(missing_bucket)]
    end.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Internal Functions                          %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

start() ->
    gen_server:start(?MODULE, [], []).

multiget(Pid, Bucket, KeyList, Concurrency, Options, Timeout) ->
    ResultList = gen_server:call(Pid, {multiget, Bucket, KeyList, Concurrency, Options}, Timeout),
    format_multiget_results(Bucket, ResultList, []).

format_multiget_results(_Bucket, [], Results) ->
    Results;
format_multiget_results(Bucket, [{Key, Reason} | List], Results) when is_binary(Key) andalso is_atom(Reason) ->
    format_multiget_results(Bucket, List, [json_encode_error(Bucket, Key, Reason) | Results]);
format_multiget_results(Bucket, [RO | List], Results) ->
    format_multiget_results(Bucket, List, [json_encode_object(RO) | Results]).

%% --------------------------------------------------------------------
%% Function: init/1
%% Description: Initiates the server
%% Returns: {ok, State}          |
%%          {ok, State, Timeout} |
%%          ignore               |
%%          {stop, Reason}
%% --------------------------------------------------------------------    
init([]) ->
    {ok, #state{}}.

%% --------------------------------------------------------------------
%% Function: handle_call/3
%% Description: Handling call messages
%% Returns: {reply, Reply, State}          |
%%          {reply, Reply, State, Timeout} |
%%          {noreply, State}               |
%%          {noreply, State, Timeout}      |
%%          {stop, Reason, Reply, State}   | (terminate/2 is called)
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_call({multiget, Bucket, KeyList, Concurrency, Options}, From, #state{} = State) ->
    {RemainingKeys, WorkerList} = launch_workers(Concurrency, Bucket, KeyList, Options),
    {noreply, State#state{from = From, bucket = Bucket, keylist = RemainingKeys, workerlist = WorkerList, options = Options, results = []}}.

%% --------------------------------------------------------------------
%% Function: handle_cast/2
%% Description: Handling cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_cast(_, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: handle_info/2
%% Description: Handling all non call/cast messages
%% Returns: {noreply, State}          |
%%          {noreply, State, Timeout} |
%%          {stop, Reason, State}            (terminate/2 is called)
%% --------------------------------------------------------------------
handle_info({K, Reason}, #state{from = F, bucket = B, keylist = RK, workerlist = WL, options = O, results = R} = State) when is_atom(Reason) ->
    case {RK, [{Key, MRef} || {Key, MRef} <- WL, Key =/= K]} of
        {[], []} ->
            gen_server:reply(F, [{K, Reason} | R]),
            {stop, "multiget completed", State};
        {[], Workers} ->
            {noreply, State#state{workerlist = Workers, results = [{K, Reason} | R]}};
        {[NextKey | KeyList], Workers} ->
            Worker = launch_worker(B, NextKey, O),
            {noreply, State#state{keylist = KeyList, workerlist = [Worker | Workers], results = [{K, Reason} | R]}}
    end;
handle_info({K, RO}, #state{from = F, bucket = B, keylist = RK, workerlist = WL, options = O, results = R} = State) ->
    case {RK, [{Key, MRef} || {Key, MRef} <- WL, Key =/= K]} of
        {[], []} ->
            gen_server:reply(F, [RO | R]),
            {stop, "multiget completed", State};
        {[], Workers} ->
            {noreply, State#state{workerlist = Workers, results = [RO | R]}};
        {[NextKey | KeyList], Workers} ->
            Worker = launch_worker(B, NextKey, O),
            {noreply, State#state{keylist = KeyList, workerlist = [Worker | Workers], results = [RO | R]}}
    end;
handle_info({'DOWN', MonitorRef, _, _, _}, #state{bucket = B, workerlist = WL, options = O} = State) ->
    case monitored_key(MonitorRef, WL) of
        none ->
            {noreply, State};
        Key ->
            Worker = launch_worker(B, Key, O),
            Workers = [Worker | remove_monitor(MonitorRef, WL)],
            {noreply, State#state{workerlist = Workers}}
    end;
handle_info(_Info, State) ->
    {noreply, State}.

%% --------------------------------------------------------------------
%% Function: terminate/2
%% Description: Shutdown the server
%% Returns: any (ignored by gen_server)
%% --------------------------------------------------------------------
terminate(_Reason, _State) ->
    ok.

%% --------------------------------------------------------------------
%% Func: code_change/3
%% Purpose: Convert process state when code is changed
%% Returns: {ok, NewState}
%% --------------------------------------------------------------------
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% Utility Functions                           %%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

determine_concurrency(Props) ->
    {Default, Max} = case {application:get_env(riak_kv, default_multiget_concurrency), application:get_env(riak_kv, max_multiget_concurrency)} of
        {undefined, undefined} ->
            {10, 20};
        {{ok, D}, undefined} when is_integer(D) andalso D > 0 ->
            {min(D, 20), 20};
        {undefined, {ok, M}} when is_integer(M) andalso M > 0 ->
            {min(10, M), M};
        {{ok, D}, {ok, M}} when is_integer(D) andalso is_integer(M) andalso D > 0 andalso M > 0 ->
            {min(D, M), M};
        _ ->
            {10, 20}
    end,
    case proplists:lookup(<<"concurrency">>, Props) of
        {_, N} when is_integer(N) andalso N > 0 ->
            min(Max, N);
        _ ->
            Default
    end.        

get_object(From, Bucket, Key, Options) when is_list(Options) ->
    {ok, C} = riak:local_client(),
    case C:get(Bucket, Key, Options) of
        {ok, RO} ->
            From ! {Key, RO};
        {error, notfound} ->
            From ! {Key, notfound};
        {error, {n_val_violation, _}} ->
            From ! {Key, n_val_violation};
        {error, {r_val_unsatisfied, _, _}} ->
            From ! {Key, r_val_unsatisfied};
        {error, timeout} ->
            From ! {Key, timeout};
        _ ->
            From ! {Key, other_error}
    end.

launch_workers(N, Bucket, KeyList, Options) ->
    launch_workers(N, Bucket, KeyList, Options, []).

launch_workers(0, _, RemainingKeys, _, WorkerList) ->
    {RemainingKeys, WorkerList};
launch_workers(_, _, [], _, WorkerList) ->
    {[], WorkerList};
launch_workers(N, Bucket, [Key | RemainingKeys], Options, WorkerList) ->
    Worker = launch_worker(Bucket, Key, Options),
    launch_workers((N - 1), Bucket, RemainingKeys, Options, [Worker | WorkerList]).

launch_worker(Bucket, Key, Options) ->
    {_, MRef} = spawn_monitor(?MODULE, get_object, [self(), Bucket, Key, Options]),
    {Key, MRef}.

monitored_key(MonitorRef, WorkerList) ->
    case [Key || {Key, MRef} <- WorkerList, MRef == MonitorRef] of
        [] ->
            none;
        [K | _] ->
            K
    end.

remove_monitor(MonitorRef, WorkerList) ->
    [{Key, MRef} || {Key, MRef} <- WorkerList, MRef =/= MonitorRef].

json_encode_error(Error) when is_atom(Error) ->
    json_encode_error(atom_to_binary(Error, latin1));
json_encode_error(Error) when is_list(Error) ->
    json_encode_error(list_to_binary(Error));
json_encode_error(Error) when is_binary(Error) ->
    json_encode_error(<<"unknown">>, <<"unknown">>, Error);
json_encode_error(Error) ->
    json_encode_error(term_to_binary(Error)).

json_encode_error(Bucket, Key, Error) when is_atom(Error) ->
    json_encode_error(Bucket, Key, atom_to_binary(Error, latin1));
json_encode_error(Bucket, Key, Error) when is_list(Error) ->
    json_encode_error(Bucket, Key, list_to_binary(Error));
json_encode_error(Bucket, Key, Error) when is_binary(Bucket) andalso is_binary(Key) andalso is_binary(Error) ->
    list_to_binary(mochijson2:encode({struct, [{<<"bucket">>, Bucket},{<<"key">>, Key},{<<"error">>, Error}]}));
json_encode_error(Bucket, Key, Error) ->
    json_encode_error(Bucket, Key, term_to_binary(Error)).

json_encode_object(RO) ->
    case encode_contents(riak_object:get_contents(RO)) of
        {ok, Contents} ->
            Response = {struct, [{<<"bucket">>, riak_object:bucket(RO)},
                                 {<<"key">>, riak_object:key(RO)},
                                 {<<"vclock">>, base64:encode(zlib:zip(term_to_binary(riak_object:vclock(RO))))},
                                 {<<"contents">>, {array, Contents}}]},
            list_to_binary(mochijson2:encode(Response));
        {error, Error} ->    
            json_encode_error(riak_object:bucket(RO), riak_object:key(RO), Error)
    end.

encode_contents(Contents) ->
    encode_contents(Contents, []).

encode_contents([], Response) when is_list(Response) ->
    {ok, Response};
encode_contents([], Response) ->
    {error, Response};    
encode_contents([{MD, V} | Contents], Response) ->   
    case is_allowed_content_type(MD) or is_deleted(MD) of
        true ->
            MDL = dict:to_list(MD),
            HL = encode_headers(MDL, []),
            JV = mochijson2:decode(V),
            C = [{<<"value">>, JV} | HL],
            encode_contents(Contents, [{struct, C} | Response]);
        false ->
            encode_contents([], non_json_contant_type)
    end.

encode_headers([], EncodedHeaderList) ->
    EncodedHeaderList;
encode_headers([{<<"X-Riak-VTag">>, VTag} | Rest], EncodedHeaderList) ->
    encode_headers(Rest, [{<<"vtag">>, list_to_binary(VTag)} | EncodedHeaderList]);
encode_headers([{<<"Links">>, LinkList} | Rest], EncodedHeaderList) ->
    LL = [{struct,[{<<"bucket">>, B},{<<"key">>, K},{<<"tag">>, T}]} || {{B, K}, T} <- LinkList],
    encode_headers(Rest, [{<<"links">>, {array, LL}} | EncodedHeaderList]);
encode_headers([{<<"content-type">>, CT} | Rest], EncodedHeaderList) ->
    encode_headers(Rest, [{<<"content-type">>, list_to_binary(CT)} | EncodedHeaderList]);
encode_headers([{<<"encoding">>, Encoding} | Rest], EncodedHeaderList) ->
    encode_headers(Rest, [{<<"encoding">>, Encoding} | EncodedHeaderList]);
encode_headers([{<<"index">>, IndexList} | Rest], EncodedHeaderList) ->
    Fun1 = fun({K,V}, Dict) ->
              case dict:find(K, Dict) of
                  {ok, List} ->
                      dict:store(K, [V | List], Dict);
                  error ->
                      dict:store(K, [V], Dict)
              end
          end,
    FormattedList = dict:to_list(lists:foldl(Fun1, dict:new(), IndexList)),
    encode_headers(Rest, [{<<"indexes">>, {struct, FormattedList}} | EncodedHeaderList]);
encode_headers([{<<"X-Riak-Last-Modified">>, TS} | Rest], EncodedHeaderList) ->
    {{Y, M, D}, {HH, MI, SS}} = calendar:now_to_universal_time(TS),
    Str = list_to_binary(io_lib:format("\~4.10.0B-\~2.10.0B-\~2.10.0B \~2.10.0B:\~2.10.0B:\~2.10.0B GMT", [Y, M, D, HH, MI, SS])),
    encode_headers(Rest, [{<<"last-modified">>, Str} | EncodedHeaderList]);
encode_headers([{<<"X-Riak-Meta">>, MetaList} | Rest], EncodedHeaderList) ->
    ML = [{list_to_binary(T), list_to_binary(V)} || {T,V} <- MetaList],
    encode_headers(Rest, [{<<"usermeta">>, {struct, ML}} | EncodedHeaderList]);
encode_headers([_ | Rest], EncodedHeaderList) ->
    encode_headers(Rest, EncodedHeaderList).

is_allowed_content_type(MD) ->
    case dict:find(<<"content-type">>, MD) of
        {ok, CT} -> 
            lists:member(CT, ?ALLOWED_CONTENT_TYPES);
        error ->
            false
    end.

is_deleted(MD) ->
    dict:is_key(<<"X-Riak-Deleted">>, MD).
