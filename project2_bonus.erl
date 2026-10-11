% Project 2 Bonus: Fault-Tolerant Gossip & Push-Sum Simulator
% COP5612 / COP5615 - Fall 2026
% Authors: Danush & Vignesh

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

    % Select nodes to fail for node failure model (node 1 stays alive to initiate)
    FailedSet = case FailureType of
        node ->
            NumFailed = round(ActualNodes * FailureRate),
            Eligible = lists:seq(2, ActualNodes),
            Shuffled = shuffle(Eligible),
            sets:from_list(lists:sublist(Shuffled, NumFailed));
        _ ->
            sets:new()
    end,

    ConnDrop = case FailureType of
        connection -> FailureRate;
        _          -> 0.0
    end,

    Pids = spawn_actors(ActualNodes, Algorithm, Master, FailedSet, ConnDrop),
    PidTuple = list_to_tuple(Pids),
    setup_topology(Topology, ActualNodes, Pids, PidTuple),

    AliveCount = ActualNodes - sets:size(FailedSet),
    start_algorithm(Algorithm, Pids),

    Res = wait_convergence(AliveCount, ActualNodes, 0),
    [Pid ! stop || Pid <- Pids],
    Res.

% Argument parser with defaults
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
                FType = parse_failure_type(FailTypeStr),
                case {Topo, Algo, FType} of
                    {error, _, _} -> {error, "Invalid topology. Choose: full, 2D, line, imp2D"};
                    {_, error, _} -> {error, "Invalid algorithm. Choose: gossip, push-sum"};
                    {_, _, error} -> {error, "Invalid failureType. Choose: node, connection"};
                    _ -> {ok, NumNodes, Topo, Algo, FailRate, FType}
                end;
            false ->
                {error, "numNodes must be > 0 and failureRate in [0.0, 1.0)"}
        end
    catch
        _:_ -> {error, "Invalid numeric arguments"}
    end;
parse_args(_) ->
    {error, "Incorrect number of arguments"}.

list_to_float_or_int(Str) ->
    case string:to_float(Str) of
        {error, no_float} -> float(list_to_integer(Str));
        {Float, _Rest}    -> Float
    end.

parse_topology(Str) ->
    case string:to_lower(Str) of
        "full"  -> full;
        "2d"    -> '2D';
        "line"  -> line;
        "imp2d" -> imp2D;
        _       -> error
    end.

parse_algorithm(Str) ->
    case string:to_lower(Str) of
        "gossip"   -> gossip;
        "push-sum" -> 'push-sum';
        "pushsum"  -> 'push-sum';
        _          -> error
    end.

parse_failure_type(Str) ->
    case string:to_lower(Str) of
        "node"       -> node;
        "connection" -> connection;
        "conn"       -> connection;
        _            -> error
    end.

round_nodes(N, Topo) when Topo =:= '2D'; Topo =:= imp2D ->
    S = ceil(math:sqrt(N)),
    S * S;
round_nodes(N, _Topo) ->
    N.

shuffle(List) ->
    [X || {_, X} <- lists:sort([{rand:uniform(), Item} || Item <- List])].

% Spawn actors
spawn_actors(N, gossip, Master, FailedSet, ConnDrop) ->
    [begin
        IsDead = sets:is_element(I, FailedSet),
        spawn(fun() -> gossip_init(Master, IsDead, ConnDrop) end)
    end || I <- lists:seq(1, N)];
spawn_actors(N, 'push-sum', Master, FailedSet, ConnDrop) ->
    [begin
        IsDead = sets:is_element(I, FailedSet),
        spawn(fun() -> push_sum_init(Master, I, IsDead, ConnDrop) end)
    end || I <- lists:seq(1, N)].

% grid coordinate neighbors helper (up, down, left, right)
grid_indices(I, S) ->
    R = (I - 1) div S,
    C = (I - 1) rem S,
    [ (R-1)*S + C + 1 || R > 0 ] ++
    [ (R+1)*S + C + 1 || R < S - 1 ] ++
    [ R*S + (C-1) + 1 || C > 0 ] ++
    [ R*S + (C+1) + 1 || C < S - 1 ].

% Topology setup
setup_topology(full, _N, Pids, PidTuple) ->
    [Pid ! {setup, {full, PidTuple, I}} || {I, Pid} <- lists:zip(lists:seq(1, length(Pids)), Pids)];

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
    [Pid ! {setup, list_to_tuple([element(X, PidTuple) || X <- grid_indices(I, S)])}
     || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)];

setup_topology(imp2D, N, Pids, PidTuple) ->
    S = ceil(math:sqrt(N)),
    [begin
        Grid = grid_indices(I, S),
        Rand = pick_shortcut(I, Grid, N),
        Pid ! {setup, list_to_tuple([element(X, PidTuple) || X <- [Rand | Grid]])}
    end || {I, Pid} <- lists:zip(lists:seq(1, N), Pids)].

pick_shortcut(I, Excluded, N) ->
    Pick = rand:uniform(N),
    case Pick =:= I orelse lists:member(Pick, Excluded) of
        true  -> pick_shortcut(I, Excluded, N);
        false -> Pick
    end.

start_algorithm(gossip, Pids) ->
    hd(Pids) ! {rumor, "rumor"};
start_algorithm('push-sum', Pids) ->
    hd(Pids) ! {start}.

% Random sending with connection drop probability
send_random({full, Pids, MyIdx}, Msg, ConnDrop) ->
    case rand:uniform() < ConnDrop of
        true  -> ok; % link failure: message dropped
        false ->
            Target = rand:uniform(tuple_size(Pids)),
            case Target of
                MyIdx -> send_random({full, Pids, MyIdx}, Msg, ConnDrop);
                _     -> element(Target, Pids) ! Msg
            end
    end;
send_random(Neighbors, Msg, ConnDrop) ->
    case rand:uniform() < ConnDrop of
        true  -> ok; % link failure: message dropped
        false ->
            case tuple_size(Neighbors) of
                0 -> ok;
                N -> element(rand:uniform(N), Neighbors) ! Msg
            end
    end.

% Dead actor loop: ignores all protocol messages
dead_loop() ->
    receive
        stop -> ok;
        _    -> dead_loop()
    end.

% Fault-aware Gossip actor
gossip_init(Master, IsDead, ConnDrop) ->
    receive
        {setup, Neighbors} ->
            case IsDead of
                true  -> dead_loop();
                false -> gossip_loop(Master, Neighbors, 0, undefined, ConnDrop)
            end;
        stop -> ok
    end.

gossip_loop(Master, Neighbors, HeardCount, Rumor, ConnDrop) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_random(Neighbors, {rumor, Msg}, ConnDrop),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, Neighbors, 1, Msg, ConnDrop);
                Count when Count < 10 ->
                    send_random(Neighbors, {rumor, Msg}, ConnDrop),
                    gossip_loop(Master, Neighbors, Count + 1, Msg, ConnDrop);
                Count ->
                    gossip_loop(Master, Neighbors, Count + 1, Msg, ConnDrop)
            end;
        tick ->
            if HeardCount < 10 ->
                send_random(Neighbors, {rumor, Rumor}, ConnDrop),
                erlang:send_after(5, self(), tick)
            ; true -> ok
            end,
            gossip_loop(Master, Neighbors, HeardCount, Rumor, ConnDrop);
        stop -> ok
    end.

% Fault-aware Push-Sum actor
push_sum_init(Master, Index, IsDead, ConnDrop) ->
    receive
        {setup, Neighbors} ->
            case IsDead of
                true  -> dead_loop();
                false -> push_sum_loop(Master, Neighbors, float(Index), 1.0, 0, float(Index), ConnDrop, false)
            end;
        stop -> ok
    end.

push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, ConnDrop, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0, HalfW = W / 2.0,
            send_random(Neighbors, {push_sum, HalfS, HalfW}, ConnDrop),
            erlang:send_after(5, self(), tick),
            push_sum_loop(Master, Neighbors, HalfS, HalfW, Consecutive, PrevRatio, ConnDrop, Terminated);

        {push_sum, Sin, Win} when Terminated ->
            send_random(Neighbors, {push_sum, Sin, Win}, ConnDrop),
            push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, ConnDrop, true);

        {push_sum, Sin, Win} ->
            NewS = S + Sin,
            NewW = W + Win,
            Ratio = NewS / NewW,
            NewConsecutive = case abs(Ratio - PrevRatio) < 1.0e-10 of
                true  -> Consecutive + 1;
                false -> 0
            end,
            HalfS = NewS / 2.0,
            HalfW = NewW / 2.0,
            send_random(Neighbors, {push_sum, HalfS, HalfW}, ConnDrop),
            case NewConsecutive >= 3 of
                true ->
                    Master ! {converged, self(), Ratio},
                    push_sum_loop(Master, Neighbors, HalfS, HalfW, NewConsecutive, Ratio, ConnDrop, true);
                false ->
                    push_sum_loop(Master, Neighbors, HalfS, HalfW, NewConsecutive, Ratio, ConnDrop, false)
            end;

        tick when not Terminated ->
            HalfS = S / 2.0, HalfW = W / 2.0,
            send_random(Neighbors, {push_sum, HalfS, HalfW}, ConnDrop),
            erlang:send_after(5, self(), tick),
            push_sum_loop(Master, Neighbors, HalfS, HalfW, Consecutive, PrevRatio, ConnDrop, false);
        tick ->
            push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, ConnDrop, true);

        stop -> ok
    end.

% Convergence tracking with guards
wait_convergence(Target, Total, Count) when Count >= Target ->
    {ok, Target, Total, Count};
wait_convergence(Target, Total, Count) ->
    receive
        {heard, _Pid}             -> wait_convergence(Target, Total, Count + 1);
        {converged, _Pid, _Ratio} -> wait_convergence(Target, Total, Count + 1)
    after 2500 ->
        {timeout, Count, Target, Total}
    end.
