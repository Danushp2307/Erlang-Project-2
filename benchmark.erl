-module(benchmark).
-export([main/1, run/3]).

main(_) ->
    io:format("Benchmarking network sizes...~n"),
    SizesGossip = [50, 100, 200, 500, 1000, 2000, 5000],
    Topologies = [full, '2D', line, imp2D],
    
    io:format("~n--- GOSSIP BENCHMARK ---~n"),
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(N) ->
            ActualN = round_nodes(N, Topo),
            case catch run(ActualN, Topo, gossip) of
                {ok, TimeUs} ->
                    io:format("Gossip, Topo=~p, N=~p: ~p us (~.2f ms)~n", [Topo, ActualN, TimeUs, TimeUs / 1000.0]);
                Error ->
                    io:format("Gossip, Topo=~p, N=~p: FAILED (~p)~n", [Topo, ActualN, Error])
            end
        end, SizesGossip)
    end, Topologies),

    SizesPushSum = [50, 100, 200, 500, 1000, 2000],
    io:format("~n--- PUSH-SUM BENCHMARK ---~n"),
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(N) ->
            ActualN = round_nodes(N, Topo),
            case catch run(ActualN, Topo, 'push-sum') of
                {ok, TimeUs} ->
                    io:format("PushSum, Topo=~p, N=~p: ~p us (~.2f ms)~n", [Topo, ActualN, TimeUs, TimeUs / 1000.0]);
                Error ->
                    io:format("PushSum, Topo=~p, N=~p: FAILED (~p)~n", [Topo, ActualN, Error])
            end
        end, SizesPushSum)
    end, Topologies),
    halt(0).

round_nodes(N, Topo) when Topo =:= '2D'; Topo =:= imp2D ->
    S = ceil(math:sqrt(N)),
    S * S;
round_nodes(N, _Topo) ->
    N.

run(N, Topology, Algorithm) ->
    Master = self(),
    Pids = spawn_actors(N, Algorithm, Master),
    PidTuple = list_to_tuple(Pids),
    setup_topology(Topology, N, Pids, PidTuple),
    
    Start = erlang:monotonic_time(microsecond),
    start_algorithm(Algorithm, Pids),
    
    Res = wait_convergence(Algorithm, N, 0, Start),
    %% Cleanup actors
    [Pid ! stop || Pid <- Pids],
    Res.

spawn_actors(N, gossip, Master) ->
    [spawn(fun() -> gossip_init(Master) end) || _ <- lists:seq(1, N)];
spawn_actors(N, 'push-sum', Master) ->
    [spawn(fun() -> push_sum_init(I, Master) end) || I <- lists:seq(1, N)].

%% Setup topology
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
    hd(Pids) ! {rumor, "RUMOR"};
start_algorithm('push-sum', Pids) ->
    hd(Pids) ! {start}.

%% ==========================================
%% GOSSIP ACTOR
%% ==========================================
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

%% ==========================================
%% PUSH-SUM ACTOR
%% ==========================================
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

wait_convergence(gossip, N, Heard, Start) ->
    receive
        {heard, _Pid} ->
            NewHeard = Heard + 1,
            if
                NewHeard >= N ->
                    {ok, erlang:monotonic_time(microsecond) - Start};
                true ->
                    wait_convergence(gossip, N, NewHeard, Start)
            end
    after 45000 ->
        {timeout, Heard, N}
    end;
wait_convergence('push-sum', N, Converged, Start) ->
    receive
        {converged, _Pid, _Ratio} ->
            NewConverged = Converged + 1,
            if
                NewConverged >= N ->
                    {ok, erlang:monotonic_time(microsecond) - Start};
                true ->
                    wait_convergence('push-sum', N, NewConverged, Start)
            end
    after 45000 ->
        {timeout, Converged, N}
    end.

