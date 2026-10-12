% Project 2: Gossip & Push-Sum Simulator
% COP5612 / COP5615 - Fall 2026
% Authors: Danush (UFID: 47244992) & Vignesh (UFID: 52658963)

-module(project2).
-export([main/1, start/3, measure_running_time/1, round_nodes/2]).

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

measure_running_time(Fun) ->
    Start = erlang:monotonic_time(microsecond),
    Res = Fun(),
    End = erlang:monotonic_time(microsecond),
    Duration = End - Start,
    {Duration, Res}.

start(NumNodes, Topology, Algorithm) ->
    ActualNodes = round_nodes(NumNodes, Topology),
    Master = self(),
    Pids = spawn_actors(ActualNodes, Algorithm, Master),
    PidTuple = list_to_tuple(Pids),
    setup_topology(Topology, ActualNodes, Pids, PidTuple),

    start_algorithm(Algorithm, Pids),

    Res = wait_convergence(ActualNodes, 0),
    [Pid ! stop || Pid <- Pids],
    case Res of
        ok -> {ok, ActualNodes};
        Other -> Other
    end.

% CLI parsing
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

% round up to nearest square for 2D topologies
round_nodes(N, Topo) when Topo =:= '2D'; Topo =:= imp2D ->
    S = ceil(math:sqrt(N)),
    S * S;
round_nodes(N, _Topo) ->
    N.

% spawn actors
spawn_actors(N, gossip, Master) ->
    [spawn(fun() -> gossip_init(Master) end) || _ <- lists:seq(1, N)];
spawn_actors(N, 'push-sum', Master) ->
    [spawn(fun() -> push_sum_init(Master, I) end) || I <- lists:seq(1, N)].

% grid coordinate neighbors helper (up, down, left, right)
grid_indices(I, S) ->
    R = (I - 1) div S,
    C = (I - 1) rem S,
    [ (R-1)*S + C + 1 || R > 0 ] ++
    [ (R+1)*S + C + 1 || R < S - 1 ] ++
    [ R*S + (C-1) + 1 || C > 0 ] ++
    [ R*S + (C+1) + 1 || C < S - 1 ].

% topology setup
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

% trigger first actor to start
start_algorithm(gossip, Pids) ->
    hd(Pids) ! {rumor, "rumor"};
start_algorithm('push-sum', Pids) ->
    hd(Pids) ! {start}.

% random message sending helper
send_random({full, Pids, MyIdx}, Msg) ->
    Target = rand:uniform(tuple_size(Pids)),
    case Target of
        MyIdx -> send_random({full, Pids, MyIdx}, Msg);
        _     -> element(Target, Pids) ! Msg
    end;
send_random(Neighbors, Msg) ->
    case tuple_size(Neighbors) of
        0 -> ok;
        N -> element(rand:uniform(N), Neighbors) ! Msg
    end.

% Gossip actor
gossip_init(Master) ->
    receive
        {setup, Neighbors} -> gossip_loop(Master, Neighbors, 0, undefined);
        stop -> ok
    end.

gossip_loop(Master, Neighbors, HeardCount, Rumor) ->
    receive
        {rumor, Msg} ->
            case HeardCount of
                0 ->
                    Master ! {heard, self()},
                    send_random(Neighbors, {rumor, Msg}),
                    erlang:send_after(5, self(), tick),
                    gossip_loop(Master, Neighbors, 1, Msg);
                Count when Count < 10 ->
                    send_random(Neighbors, {rumor, Msg}),
                    gossip_loop(Master, Neighbors, Count + 1, Msg);
                Count ->
                    gossip_loop(Master, Neighbors, Count + 1, Msg)
            end;
        tick ->
            if HeardCount < 10 ->
                send_random(Neighbors, {rumor, Rumor}),
                erlang:send_after(5, self(), tick)
            ; true -> ok
            end,
            gossip_loop(Master, Neighbors, HeardCount, Rumor);
        stop -> ok
    end.

% Push-Sum actor
push_sum_init(Master, Index) ->
    receive
        {setup, Neighbors} ->
            push_sum_loop(Master, Neighbors, float(Index), 1.0, 0, float(Index), false);
        stop -> ok
    end.

push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, Terminated) ->
    receive
        {start} ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_random(Neighbors, {push_sum, HalfS, HalfW}),
            erlang:send_after(5, self(), tick),
            push_sum_loop(Master, Neighbors, HalfS, HalfW, Consecutive, PrevRatio, Terminated);

        {push_sum, Sin, Win} when Terminated ->
            % relay incoming values so total s and w stay conserved across the network
            send_random(Neighbors, {push_sum, Sin, Win}),
            push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, true);

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
            send_random(Neighbors, {push_sum, HalfS, HalfW}),
            case NewConsecutive >= 3 of
                true ->
                    Master ! {converged, self(), Ratio},
                    push_sum_loop(Master, Neighbors, HalfS, HalfW, NewConsecutive, Ratio, true);
                false ->
                    push_sum_loop(Master, Neighbors, HalfS, HalfW, NewConsecutive, Ratio, false)
            end;

        tick when not Terminated ->
            HalfS = S / 2.0,
            HalfW = W / 2.0,
            send_random(Neighbors, {push_sum, HalfS, HalfW}),
            erlang:send_after(5, self(), tick),
            push_sum_loop(Master, Neighbors, HalfS, HalfW, Consecutive, PrevRatio, false);
        tick ->
            push_sum_loop(Master, Neighbors, S, W, Consecutive, PrevRatio, true);

        stop -> ok
    end.

% Convergence tracking
wait_convergence(Target, Count) when Count >= Target ->
    ok;
wait_convergence(Target, Count) ->
    receive
        {heard, _Pid}             -> wait_convergence(Target, Count + 1);
        {converged, _Pid, _Ratio} -> wait_convergence(Target, Count + 1)
    after 60000 ->
        {timeout, Count, Target}
    end.
