%%% ====================================================================
%%% COP5612 / COP5615 - Project 2: Gossip Simulator
%%% Authors: Distributed Systems Team
%%% Problem: Asynchronous Gossip and Push-Sum simulator across topologies
%%% Topologies: full, 2D, line, imp2D
%%% Algorithms: gossip, push-sum
%%% ====================================================================

-module(project2).
-export([main/1, start/3, measure_running_time/1, round_nodes/2]).

%% Command-line entry point for escript or erl -s
main(Args) ->
    case parse_args(Args) of
        {ok, NumNodes, Topology, Algorithm} ->
            {Duration, Result} = measure_running_time(fun() ->
                start(NumNodes, Topology, Algorithm)
            end),
            case Result of
                {ok, ActualNodes} ->
                    io:format("Convergence achieved for ~p nodes.~n", [ActualNodes]),
                    io:format("Convergence time: ~p microseconds (~.2f ms)~n", [Duration, Duration / 1000.0]);
                {timeout, Converged, Total} ->
                    io:format("Simulation timed out. Reached ~p / ~p nodes.~n", [Converged, Total]),
                    io:format("Time elapsed before timeout: ~p microseconds (~.2f ms)~n", [Duration, Duration / 1000.0]);
                {error, Reason} ->
                    io:format("Error during simulation: ~p~n", [Reason])
            end,
            halt(0);
        {error, Msg} ->
            io:format("Usage: project2 numNodes topology algorithm~n"),
            io:format("  numNodes:  Integer > 0~n"),
            io:format("  topology:  full | 2D | line | imp2D~n"),
            io:format("  algorithm: gossip | push-sum~n"),
            io:format("Error: ~s~n", [Msg]),
            halt(1)
    end.

%% Timing function matching assignment specification
measure_running_time(Fun) ->
    Start = erlang:monotonic_time(microsecond),
    Res = Fun(),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    {Duration, Res}.

%% Main API function
start(NumNodes, Topology, Algorithm) ->
    ActualNodes = round_nodes(NumNodes, Topology),
    Master = self(),
    Pids = spawn_actors(ActualNodes, Algorithm, Master),
    PidTuple = list_to_tuple(Pids),
    setup_topology(Topology, ActualNodes, Pids, PidTuple),
    
    %% Initiate algorithm
    start_algorithm(Algorithm, Pids),
    
    %% Wait for convergence
    Res = wait_convergence(Algorithm, ActualNodes, 0),
    %% Clean up spawned actors
    [Pid ! stop || Pid <- Pids],
    case Res of
        ok -> {ok, ActualNodes};
        Other -> Other
    end.

%% Parse and validate command line arguments
parse_args([NumNodesStr, TopoStr, AlgoStr]) ->
    try
        NumNodes = list_to_integer(NumNodesStr),
        case NumNodes > 0 of
            true ->
                Topo = parse_topology(TopoStr),
                Algo = parse_algorithm(AlgoStr),
                case {Topo, Algo} of
                    {error, _} -> {error, "Invalid topology. Choose: full, 2D, line, imp2D"};
                    {_, error} -> {error, "Invalid algorithm. Choose: gossip, push-sum"};
                    _ -> {ok, NumNodes, Topo, Algo}
                end;
            false ->
                {error, "numNodes must be a positive integer"}
        end
    catch
        _:_ -> {error, "numNodes must be an integer"}
    end;
parse_args(_) ->
    {error, "Incorrect number of arguments"}.

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

%% Round up nodes for 2D grid topologies to the nearest perfect square
round_nodes(N, Topo) when Topo =:= '2D'; Topo =:= imp2D ->
    S = ceil(math:sqrt(N)),
    S * S;
round_nodes(N, _Topo) ->
    N.

%% ====================================================================
%% TOPOLOGY GENERATION & SETUP
%% ====================================================================
spawn_actors(N, gossip, Master) ->
    [spawn(fun() -> gossip_init(Master) end) || _ <- lists:seq(1, N)];
spawn_actors(N, 'push-sum', Master) ->
    [spawn(fun() -> push_sum_init(I, Master) end) || I <- lists:seq(1, N)].

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
%% GOSSIP ACTOR IMPLEMENTATION
%% ====================================================================
gossip_init(Master) ->
    receive
        {setup, NeighborTuple} ->
            gossip_loop(Master, NeighborTuple, 0, undefined);
        {setup_full, N, MyIdx, PidTuple} ->
            gossip_loop_full(Master, N, MyIdx, PidTuple, 0, undefined);
        stop -> ok
    end.

gossip_loop(Master, NeighborTuple, HeardCount, Rumor) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_tuple(NeighborTuple, {rumor, Msg}),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, NeighborTuple, 1, Msg);
                Count when Count < 10 ->
                    send_tuple(NeighborTuple, {rumor, Msg}),
                    gossip_loop(Master, NeighborTuple, Count + 1, Msg);
                Count ->
                    gossip_loop(Master, NeighborTuple, Count + 1, Msg)
            end;
        tick ->
            if
                HeardCount < 10 ->
                    send_tuple(NeighborTuple, {rumor, Rumor}),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, NeighborTuple, HeardCount, Rumor);
                true ->
                    gossip_loop(Master, NeighborTuple, HeardCount, Rumor)
            end;
        stop -> ok
    end.

gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, Rumor) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_full(N, MyIdx, PidTuple, {rumor, Msg}),
                    erlang:send_after(5, self(), tick),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, 1, Msg);
                Count when Count < 10 ->
                    send_full(N, MyIdx, PidTuple, {rumor, Msg}),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, Count + 1, Msg);
                Count ->
                    gossip_loop_full(Master, N, MyIdx, PidTuple, Count + 1, Msg)
            end;
        tick ->
            if
                HeardCount < 10 ->
                    send_full(N, MyIdx, PidTuple, {rumor, Rumor}),
                    erlang:send_after(5, self(), tick),
                    gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, Rumor);
                true ->
                    gossip_loop_full(Master, N, MyIdx, PidTuple, HeardCount, Rumor)
            end;
        stop -> ok
    end.

send_tuple(NeighborTuple, Msg) ->
    Size = tuple_size(NeighborTuple),
    if
        Size > 0 ->
            Idx = rand:uniform(Size),
            element(Idx, NeighborTuple) ! Msg;
        true -> ok
    end.

send_full(N, MyIdx, PidTuple, Msg) ->
    Target = rand:uniform(N),
    if
        Target =:= MyIdx -> send_full(N, MyIdx, PidTuple, Msg);
        true -> element(Target, PidTuple) ! Msg
    end.

%% ====================================================================
%% PUSH-SUM ACTOR IMPLEMENTATION
%% ====================================================================
push_sum_init(Index, Master) ->
    receive
        {setup, NeighborTuple} ->
            push_sum_loop(float(Index), 1.0, 0, float(Index), NeighborTuple, Master, false);
        {setup_full, N, MyIdx, PidTuple} ->
            push_sum_loop_full(float(Index), 1.0, 0, float(Index), N, MyIdx, PidTuple, Master, false);
        stop -> ok
    end.

push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}),
            erlang:send_after(5, self(), tick),
            push_sum_loop(HalfS, HalfW, Consecutive, PrevRatio, NeighborTuple, Master, Terminated);
        {push_sum, S_in, W_in} ->
            if
                Terminated ->
                    send_tuple(NeighborTuple, {push_sum, S_in, W_in}),
                    push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, true);
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
                            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}),
                            push_sum_loop(HalfS, HalfW, NewConsecutive, NewRatio, NeighborTuple, Master, true);
                        true ->
                            send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}),
                            push_sum_loop(HalfS, HalfW, NewConsecutive, NewRatio, NeighborTuple, Master, false)
                    end
            end;
        tick ->
            if
                not Terminated ->
                    HalfS = S / 2.0,
                    HalfW = W / 2.0,
                    send_tuple(NeighborTuple, {push_sum, HalfS, HalfW}),
                    erlang:send_after(5, self(), tick),
                    push_sum_loop(HalfS, HalfW, Consecutive, PrevRatio, NeighborTuple, Master, Terminated);
                true ->
                    push_sum_loop(S, W, Consecutive, PrevRatio, NeighborTuple, Master, Terminated)
            end;
        stop -> ok
    end.

push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}),
            erlang:send_after(5, self(), tick),
            push_sum_loop_full(HalfS, HalfW, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, Terminated);
        {push_sum, S_in, W_in} ->
            if
                Terminated ->
                    send_full(N, MyIdx, PidTuple, {push_sum, S_in, W_in}),
                    push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, true);
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
                            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}),
                            push_sum_loop_full(HalfS, HalfW, NewConsecutive, NewRatio, N, MyIdx, PidTuple, Master, true);
                        true ->
                            send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}),
                            push_sum_loop_full(HalfS, HalfW, NewConsecutive, NewRatio, N, MyIdx, PidTuple, Master, false)
                    end
            end;
        tick ->
            if
                not Terminated ->
                    HalfS = S / 2.0,
                    HalfW = W / 2.0,
                    send_full(N, MyIdx, PidTuple, {push_sum, HalfS, HalfW}),
                    erlang:send_after(5, self(), tick),
                    push_sum_loop_full(HalfS, HalfW, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, Terminated);
                true ->
                    push_sum_loop_full(S, W, Consecutive, PrevRatio, N, MyIdx, PidTuple, Master, Terminated)
            end;
        stop -> ok
    end.

%% ====================================================================
%% CONVERGENCE TRACKING
%% ====================================================================
wait_convergence(gossip, N, Heard) ->
    receive
        {heard, _Pid} ->
            NewHeard = Heard + 1,
            if
                NewHeard >= N -> ok;
                true -> wait_convergence(gossip, N, NewHeard)
            end
    after 60000 ->
        {timeout, Heard, N}
    end;
wait_convergence('push-sum', N, Converged) ->
    receive
        {converged, _Pid, _Ratio} ->
            NewConverged = Converged + 1,
            if
                NewConverged >= N -> ok;
                true -> wait_convergence('push-sum', N, NewConverged)
            end
    after 60000 ->
        {timeout, Converged, N}
    end.
