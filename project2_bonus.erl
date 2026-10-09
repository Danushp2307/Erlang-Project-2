%%% ====================================================================
%%% COP5612 / COP5615 - Project 2 Bonus: Gossip Simulator with Failures
%%% Authors: Distributed Systems Team
%%% Problem: Fault-tolerant Asynchronous Gossip and Push-Sum simulator
%%% Failure Models:
%%%   1. Node Crash Failures (permanent node death / crash)
%%%   2. Transient Connection / Link Failures (packet / message drop)
%%% Parameters:
%%%   - FailureRate: float in [0.0, 1.0)
%%%   - FailureType: node | connection
%%% ====================================================================

-module(project2_bonus).
-export([main/1, start/5, measure_running_time/1, round_nodes/2]).

main(Args) ->
    case parse_args(Args) of
        {ok, NumNodes, Topology, Algorithm, FailureRate, FailureType} ->
            {Duration, Result} = measure_running_time(fun() ->
                start(NumNodes, Topology, Algorithm, FailureRate, FailureType)
            end),
            case Result of
                {ok, AliveNodes, TotalNodes, ReachedNodes} ->
                    io:format("==================================================~n"),
                    io:format("Simulation Complete with Failure Model: ~p (~.1f% failure)~n", [FailureType, FailureRate * 100]),
                    io:format("Total Nodes: ~p | Surviving Nodes: ~p | Reached Nodes: ~p~n", [TotalNodes, AliveNodes, ReachedNodes]),
                    Coverage = case AliveNodes of 0 -> 0.0; _ -> (ReachedNodes / AliveNodes) * 100.0 end,
                    io:format("Coverage among alive nodes: ~.2f%~n", [Coverage]),
                    io:format("Convergence time: ~p microseconds (~.2f ms)~n", [Duration, Duration / 1000.0]),
                    io:format("==================================================~n");
                {timeout, ReachedNodes, AliveNodes, TotalNodes} ->
                    io:format("==================================================~n"),
                    io:format("Simulation TIMED OUT with Failure Model: ~p (~.1f% failure)~n", [FailureType, FailureRate * 100]),
                    io:format("Total Nodes: ~p | Alive: ~p | Reached: ~p~n", [TotalNodes, AliveNodes, ReachedNodes]),
                    Coverage = case AliveNodes of 0 -> 0.0; _ -> (ReachedNodes / AliveNodes) * 100.0 end,
                    io:format("Coverage reached: ~.2f%~n", [Coverage]),
                    io:format("Time elapsed before timeout: ~p microseconds (~.2f ms)~n", [Duration, Duration / 1000.0]),
                    io:format("==================================================~n");
                {error, Reason} ->
                    io:format("Error: ~p~n", [Reason])
            end,
            halt(0);
        {error, Msg} ->
            io:format("Usage: project2_bonus numNodes topology algorithm [failureRate] [failureType]~n"),
            io:format("  numNodes:    Integer > 0~n"),
            io:format("  topology:    full | 2D | line | imp2D~n"),
            io:format("  algorithm:   gossip | push-sum~n"),
            io:format("  failureRate: Float between 0.0 and 1.0 (default: 0.1)~n"),
            io:format("  failureType: node | connection (default: node)~n"),
            io:format("Error: ~s~n", [Msg]),
            halt(1)
    end.

measure_running_time(Fun) ->
    Start = erlang:monotonic_time(microsecond),
    Res = Fun(),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    {Duration, Res}.

start(NumNodes, Topology, Algorithm, FailureRate, FailureType) ->
    ActualNodes = round_nodes(NumNodes, Topology),
    Master = self(),
    
    %% Determine which nodes will fail for node failure model
    FailedSet = case FailureType of
        node ->
            NumFailed = round(ActualNodes * FailureRate),
            %% First node should not be failed to allow protocol start
            Eligible = lists:seq(2, ActualNodes),
            Shuffled = shuffle(Eligible),
            sets:from_list(lists:sublist(Shuffled, NumFailed));
        _ ->
            sets:new()
    end,
    
    Pids = spawn_actors(ActualNodes, Algorithm, Master, FailedSet, FailureRate, FailureType),
    PidTuple = list_to_tuple(Pids),
    setup_topology(Topology, ActualNodes, Pids, PidTuple),
    
    AliveCount = ActualNodes - sets:size(FailedSet),
    
    %% Initiate algorithm from node 1
    start_algorithm(Algorithm, Pids),
    
    %% Wait for convergence
    Res = wait_convergence(Algorithm, AliveCount, ActualNodes, 0),
    [Pid ! stop || Pid <- Pids],
    Res.

%% Parse command line arguments
parse_args([NumNodesStr, TopoStr, AlgoStr]) ->
    parse_args([NumNodesStr, TopoStr, AlgoStr, "0.1", "node"]);
parse_args([NumNodesStr, TopoStr, AlgoStr, FailRateStr]) ->
    parse_args([NumNodesStr, TopoStr, AlgoStr, FailRateStr, "node"]);
parse_args([NumNodesStr, TopoStr, AlgoStr, FailRateStr, FailTypeStr]) ->
    try
        NumNodes = list_to_integer(NumNodesStr),
        FailRate = list_to_float_or_int(FailRateStr),
        case NumNodes > 0 andalso FailRate >= 0.0 andalso FailRate < 1.0 of
            true ->
                Topo = parse_topology(TopoStr),
                Algo = parse_algorithm(AlgoStr),
                FailType = parse_failure_type(FailTypeStr),
                case {Topo, Algo, FailType} of
                    {error, _, _} -> {error, "Invalid topology. Choose: full, 2D, line, imp2D"};
                    {_, error, _} -> {error, "Invalid algorithm. Choose: gossip, push-sum"};
                    {_, _, error} -> {error, "Invalid failureType. Choose: node, connection"};
                    _ -> {ok, NumNodes, Topo, Algo, FailRate, FailType}
                end;
            false ->
                {error, "numNodes must be > 0 and failureRate must be between 0.0 and 1.0"}
        end
    catch
        _:_ -> {error, "Invalid arguments format"}
    end;
parse_args(_) ->
    {error, "Incorrect number of arguments"}.

list_to_float_or_int(Str) ->
    case string:to_float(Str) of
        {error, no_float} -> float(list_to_integer(Str));
        {FloatVal, _Rest} -> FloatVal
    end.

parse_topology(Str) ->
    case string:to_lower(Str) of
        "full" -> full;
        "2d" -> '2D';
        "line" -> line;
        "imp2d" -> imp2D;
        _ -> error
    end.

parse_algorithm(Str) ->
    case string:to_lower(Str) of
        "gossip" -> gossip;
        "push-sum" -> 'push-sum';
        "pushsum" -> 'push-sum';
        _ -> error
    end.

parse_failure_type(Str) ->
    case string:to_lower(Str) of
        "node" -> node;
        "connection" -> connection;
        "conn" -> connection;
        "link" -> connection;
        _ -> error
    end.

round_nodes(N, Topo) when Topo =:= '2D'; Topo =:= imp2D ->
    S = ceil(math:sqrt(N)),
    S * S;
round_nodes(N, _Topo) ->
    N.

shuffle(List) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), Item} || Item <- List])].

%% ====================================================================
%% TOPOLOGY GENERATION & SETUP
%% ====================================================================
spawn_actors(N, gossip, Master, FailedSet, DropRate, FailType) ->
    [spawn(fun() ->
        IsDead = sets:is_element(I, FailedSet),
        ConnDrop = case FailType of connection -> DropRate; _ -> 0.0 end,
        gossip_init(Master, IsDead, ConnDrop)
    end) || I <- lists:seq(1, N)];
spawn_actors(N, 'push-sum', Master, FailedSet, DropRate, FailType) ->
    [spawn(fun() ->
        IsDead = sets:is_element(I, FailedSet),
        ConnDrop = case FailType of connection -> DropRate; _ -> 0.0 end,
        push_sum_init(I, Master, IsDead, ConnDrop)
    end) || I <- lists:seq(1, N)].

setup_topology(full, N, Pids, PidTuple) ->
    [Pid ! {setup_full, N, I, PidTuple} || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)];
setup_topology(line, N, Pids, PidTuple) ->
    [begin
        Neighbors = case I of
            1 -> [element(2, PidTuple)];
            N -> [element(N - 1, PidTuple)];
            _ -> [element(I - 1, PidTuple), element(I + 1, PidTuple)]
        end,
        Pid ! {setup, list_to_tuple(Neighbors)}
    end || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)];
setup_topology('2D', N, Pids, PidTuple) ->
    S = ceil(math:sqrt(N)),
    [begin
        R = (I - 1) div S,
        C = (I - 1) rem S,
        Neighbors = [
            element((R-1)*S + C + 1, PidTuple) || R > 0
        ] ++ [
            element((R+1)*S + C + 1, PidTuple) || R < S - 1
        ] ++ [
            element(R*S + (C-1) + 1, PidTuple) || C > 0
        ] ++ [
            element(R*S + (C+1) + 1, PidTuple) || C < S - 1
        ],
        Pid ! {setup, list_to_tuple(Neighbors)}
    end || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)];
setup_topology(imp2D, N, Pids, PidTuple) ->
    S = ceil(math:sqrt(N)),
    [begin
        R = (I - 1) div S,
        C = (I - 1) rem S,
        GridIndices = [
            (R-1)*S + C + 1 || R > 0
        ] ++ [
            (R+1)*S + C + 1 || R < S - 1
        ] ++ [
            R*S + (C-1) + 1 || C > 0
        ] ++ [
            R*S + (C+1) + 1 || C < S - 1
        ],
        RandIdx = pick_random_excluding(I, GridIndices, N),
        AllIndices = [RandIdx | GridIndices],
        Neighbors = [element(Idx, PidTuple) || Idx <- AllIndices],
        Pid ! {setup, list_to_tuple(Neighbors)}
    end || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)].

pick_random_excluding(I, ExcludeList, N) ->
    Candidate = rand:uniform(N),
    case Candidate =:= I orelse lists:member(Candidate, ExcludeList) of
        true -> pick_random_excluding(I, ExcludeList, N);
        false -> Candidate
    end.

start_algorithm(gossip, Pids) ->
    hd(Pids) ! {rumor, "UF_GOSSIP_FACT"};
start_algorithm('push-sum', Pids) ->
    hd(Pids) ! {start}.

%% ====================================================================
%% FAULT-AWARE GOSSIP ACTOR
%% ====================================================================
gossip_init(Master, IsDead, ConnDrop) ->
    receive
        {setup, NeighborTuple} ->
            case IsDead of
                true -> dead_loop();
                false -> gossip_loop(Master, NeighborTuple, 0, ConnDrop, undefined)
            end;
        {setup_full, N, MyIdx, PidTuple} ->
            case IsDead of
                true -> dead_loop();
                false -> gossip_loop_full(Master, N, MyIdx, PidTuple, 0, ConnDrop, undefined)
            end;
        stop -> ok
    end.

dead_loop() ->
    receive
        stop -> ok;
        _Ignored -> dead_loop()
    end.

gossip_loop(Master, NeighborTuple, HeardCount, ConnDrop, Rumor) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_tuple(NeighborTuple, {rumor, Msg}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, NeighborTuple, 1, ConnDrop, Msg);
                Count when Count < 10 ->
                    send_tuple(NeighborTuple, {rumor, Msg}, ConnDrop),
                    gossip_loop(Master, NeighborTuple, Count + 1, ConnDrop, Msg);
                Count ->
                    gossip_loop(Master, NeighborTuple, Count + 1, ConnDrop, Msg)
            end;
        tick ->
            if
                HeardCount < 10 ->
                    send_tuple(NeighborTuple, {rumor, Rumor}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, NeighborTuple, HeardCount, ConnDrop, Rumor);
                true ->
                    gossip_loop(Master, NeighborTuple, HeardCount, ConnDrop, Rumor)
            end;
        stop -> ok
    end.

gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, ConnDrop, Rumor) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_full(N, MyIdx, PidTuple, {rumor, Msg}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, 1, ConnDrop, Msg);
                Count when Count < 10 ->
                    send_full(N, MyIdx, PidTuple, {rumor, Msg}, ConnDrop),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, Count + 1, ConnDrop, Msg);
                Count ->
                    gossip_loop_full(Master, N, MyIdx, PidTuple, Count + 1, ConnDrop, Msg)
            end;
        tick ->
            if
                HeardCount < 10 ->
                    send_full(N, MyIdx, PidTuple, {rumor, Rumor}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, ConnDrop, Rumor);
                true ->
                    gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, ConnDrop, Rumor)
            end;
        stop -> ok
    end.

send_tuple(NeighborTuple, Msg, ConnDrop) ->
    case rand:uniform() < ConnDrop of
        true -> ok; %% Link failure: message dropped
        false ->
            Size = tuple_size(NeighborTuple),
            if
                Size > 0 ->
                    Idx = rand:uniform(Size),
                    element(Idx, NeighborTuple) ! Msg;
                true -> ok
            end
    end.

send_full(N, MyIdx, PidTuple, Msg, ConnDrop) ->
    case rand:uniform() < ConnDrop of
        true -> ok; %% Link failure: message dropped
        false ->
            Target = rand:uniform(N),
            if
                Target =:= MyIdx -> send_full(N, MyIdx, PidTuple, Msg, ConnDrop);
                true -> element(Target, PidTuple) ! Msg
            end
    end.

%% ====================================================================
%% FAULT-AWARE PUSH-SUM ACTOR
%% ====================================================================
push_sum_init(Index, Master, IsDead, ConnDrop) ->
    receive
        {setup, NeighborTuple} ->
            case IsDead of
                true -> dead_loop();
                false -> push_sum_loop(float(Index), 1.0, 0, float(Index), NeighborTuple, Master, ConnDrop, false)
            end;
        {setup_full, N, MyIdx, PidTuple} ->
            case IsDead of
                true -> dead_loop();
                false -> push_sum_loop_full(float(Index), 1.0, 0, float(Index), N, MyIdx, PidTuple, Master, ConnDrop, false)
            end;
        stop -> ok
    end.

push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, ConnDrop, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}, ConnDrop),
            erlang:send_after(5, self(), tick),
            push_sum_loop(HalfS, HalfW, Consecutive, PrevRatio, NeighborTuple, Master, ConnDrop, Terminated);
        {push_sum, S_in, W_in} ->
            if
                Terminated ->
                    send_tuple(NeighborTuple, {push_sum, S_in, W_in}, ConnDrop),
                    push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, ConnDrop, true);
                true ->
                    NewS = S + S_in,
                    NewW = W + W_in,
                    NewRatio = NewS / NewW,
                    Diff = abs(NewRatio - PrevRatio),
                    NewConsecutive = if
                        Diff < 1.0e-10 -> Consecutive + 1;
                        true -> 0
                    end,
                    HalfS = NewS / 2.0,
                    HalfW = NewW / 2.0,
                    if
                        NewConsecutive >= 3 ->
                            Master ! {converged, self(), NewRatio},
                            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                            push_sum_loop(HalfS, HalfW, NewConsecutive, NewRatio, NeighborTuple, Master, ConnDrop, true);
                        true ->
                            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                            push_sum_loop(HalfS, HalfW, NewConsecutive, NewRatio, NeighborTuple, Master, ConnDrop, false)
                    end
            end;
        tick ->
            if
                not Terminated ->
                    HalfS = S / 2.0,
                    HalfW = W / 2.0,
                    send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    push_sum_loop(HalfS, HalfW, Consecutive, PrevRatio, NeighborTuple, Master, ConnDrop, Terminated);
                true ->
                    push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, ConnDrop, Terminated)
            end;
        stop -> ok
    end.

push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, ConnDrop, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}, ConnDrop),
            erlang:send_after(5, self(), tick),
            push_sum_loop_full(HalfS, HalfW, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, ConnDrop, Terminated);
        {push_sum, S_in, W_in} ->
            if
                Terminated ->
                    send_full(N, MyIdx, PidTuple, {push_sum, S_in, W_in}, ConnDrop),
                    push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, ConnDrop, true);
                true ->
                    NewS = S + S_in,
                    NewW = W + W_in,
                    NewRatio = NewS / NewW,
                    Diff = abs(NewRatio - PrevRatio),
                    NewConsecutive = if
                        Diff < 1.0e-10 -> Consecutive + 1;
                        true -> 0
                    end,
                    HalfS = NewS / 2.0,
                    HalfW = NewW / 2.0,
                    if
                        NewConsecutive >= 3 ->
                            Master ! {converged, self(), NewRatio},
                            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                            push_sum_loop_full(HalfS, HalfW, NewConsecutive, NewRatio, N, MyIdx, PidTuple, Master, ConnDrop, true);
                        true ->
                            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                            push_sum_loop_full(HalfS, HalfW, NewConsecutive, NewRatio, N, MyIdx, PidTuple, Master, ConnDrop, false)
                    end
            end;
        tick ->
            if
                not Terminated ->
                    HalfS = S / 2.0,
                    HalfW = W / 2.0,
                    send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    push_sum_loop_full(HalfS, HalfW, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, ConnDrop, Terminated);
                true ->
                    push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, ConnDrop, Terminated)
            end;
        stop -> ok
    end.

%% ====================================================================
%% CONVERGENCE TRACKING
%% ====================================================================
wait_convergence(gossip, AliveCount, TotalNodes, Heard) ->
    receive
        {heard, _Pid} ->
            NewHeard = Heard + 1,
            if
                NewHeard >= AliveCount ->
                    {ok, AliveCount, TotalNodes, NewHeard};
                true ->
                    wait_convergence(gossip, AliveCount, TotalNodes, NewHeard)
            end
    after 2500 ->
        {timeout, Heard, AliveCount, TotalNodes}
    end;
wait_convergence('push-sum', AliveCount, TotalNodes, Converged) ->
    receive
        {converged, _Pid, _Ratio} ->
            NewConverged = Converged + 1,
            if
                NewConverged >= AliveCount ->
                    {ok, AliveCount, TotalNodes, NewConverged};
                true ->
                    wait_convergence('push-sum', AliveCount, TotalNodes, NewConverged)
            end
    after 2500 ->
        {timeout, Converged, AliveCount, TotalNodes}
    end.
