-module(collect_data).
-export([main/1]).

main(_) ->
    io:format("Starting data collection for Main Report...~n"),
    collect_main_data(),
    io:format("Starting data collection for Bonus Report...~n"),
    collect_bonus_data(),
    io:format("Data collection completed successfully!~n"),
    halt(0).

collect_main_data() ->
    {ok, File} = file:open("main_benchmark_data.csv", [write]),
    io:format(File, "algorithm,topology,n,actual_n,time_us,time_ms~n", []),
    
    GossipSizes = [50, 100, 250, 500, 1000, 2000, 5000, 10000],
    Topos = [full, '2D', line, imp2D],
    
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(N) ->
            %% For line at 10000, skip if too slow
            case (Topo =:= line andalso N > 3000) of
                true -> ok;
                false ->
                    ActualN = project2:round_nodes(N, Topo),
                    Times = run_reps(fun() ->
                        {Duration, Res} = project2:measure_running_time(fun() ->
                            project2:start(ActualN, Topo, gossip)
                        end),
                        case Res of
                            {ok, _} -> Duration;
                            _ -> error
                        end
                    end, 3),
                    case Times of
                        [] -> ok;
                        _ ->
                            AvgUs = lists:sum(Times) / length(Times),
                            AvgMs = AvgUs / 1000.0,
                            io:format("Gossip ~p N=~p -> ~.2f ms~n", [Topo, ActualN, AvgMs]),
                            io:format(File, "gossip,~p,~p,~p,~.2f,~.4f~n", [Topo, N, ActualN, AvgUs, AvgMs])
                    end
            end
        end, GossipSizes)
    end, Topos),

    PushSumSizes = [50, 100, 250, 500, 1000, 2000, 5000],
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(N) ->
            case (Topo =:= line andalso N > 2000) of
                true -> ok;
                false ->
                    ActualN = project2:round_nodes(N, Topo),
                    Times = run_reps(fun() ->
                        {Duration, Res} = project2:measure_running_time(fun() ->
                            project2:start(ActualN, Topo, 'push-sum')
                        end),
                        case Res of
                            {ok, _} -> Duration;
                            _ -> error
                        end
                    end, 3),
                    case Times of
                        [] -> ok;
                        _ ->
                            AvgUs = lists:sum(Times) / length(Times),
                            AvgMs = AvgUs / 1000.0,
                            io:format("PushSum ~p N=~p -> ~.2f ms~n", [Topo, ActualN, AvgMs]),
                            io:format(File, "push-sum,~p,~p,~p,~.2f,~.4f~n", [Topo, N, ActualN, AvgUs, AvgMs])
                    end
            end
        end, PushSumSizes)
    end, Topos),
    file:close(File).

collect_bonus_data() ->
    {ok, File} = file:open("bonus_benchmark_data.csv", [write]),
    io:format(File, "model,param,topology,n,coverage_pct,time_us,time_ms~n", []),
    
    %% Experiment 1: Node Failure Rate vs Coverage & Time (N=200, imp2D, 2D, line, full)
    NodeRates = [0.0, 0.05, 0.10, 0.15, 0.20, 0.25, 0.30, 0.40],
    Topos = [full, '2D', line, imp2D],
    FixedN = 196, %% perfect square 14x14
    
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(Rate) ->
            Results = run_reps(fun() ->
                {Duration, Res} = project2_bonus:measure_running_time(fun() ->
                    project2_bonus:start(FixedN, Topo, gossip, Rate, node)
                end),
                case Res of
                    {ok, Alive, _Total, Reached} ->
                        Cov = (Reached / Alive) * 100.0,
                        {Cov, Duration};
                    {timeout, Reached, Alive, _Total} ->
                        Cov = (Reached / Alive) * 100.0,
                        {Cov, Duration}
                end
            end, 3),
            AvgCov = lists:sum([C || {C, _} <- Results]) / length(Results),
            AvgUs = lists:sum([T || {_, T} <- Results]) / length(Results),
            AvgMs = AvgUs / 1000.0,
            io:format("Bonus NodeFail Topo=~p Rate=~p -> Cov=~.1f%% Time=~.2f ms~n", [Topo, Rate, AvgCov, AvgMs]),
            io:format(File, "node,~.2f,~p,~p,~.2f,~.2f,~.4f~n", [Rate, Topo, FixedN, AvgCov, AvgUs, AvgMs])
        end, NodeRates)
    end, Topos),

    %% Experiment 2: Connection Drop Rate vs Convergence Time (N=196, full, 2D, imp2D)
    ConnRates = [0.0, 0.10, 0.20, 0.30, 0.40, 0.50, 0.60],
    ConnTopos = [full, '2D', imp2D],
    lists:foreach(fun(Topo) ->
        lists:foreach(fun(Rate) ->
            Results = run_reps(fun() ->
                {Duration, Res} = project2_bonus:measure_running_time(fun() ->
                    project2_bonus:start(FixedN, Topo, gossip, Rate, connection)
                end),
                case Res of
                    {ok, Alive, _Total, Reached} ->
                        Cov = (Reached / Alive) * 100.0,
                        {Cov, Duration};
                    {timeout, Reached, Alive, _Total} ->
                        Cov = (Reached / Alive) * 100.0,
                        {Cov, Duration}
                end
            end, 3),
            AvgCov = lists:sum([C || {C, _} <- Results]) / length(Results),
            AvgUs = lists:sum([T || {_, T} <- Results]) / length(Results),
            AvgMs = AvgUs / 1000.0,
            io:format("Bonus ConnDrop Topo=~p Rate=~p -> Cov=~.1f%% Time=~.2f ms~n", [Topo, Rate, AvgCov, AvgMs]),
            io:format(File, "connection,~.2f,~p,~p,~.2f,~.2f,~.4f~n", [Rate, Topo, FixedN, AvgCov, AvgUs, AvgMs])
        end, ConnRates)
    end, ConnTopos),
    file:close(File).

run_reps(Fun, Reps) ->
    run_reps(Fun, Reps, []).
run_reps(_Fun, 0, Acc) ->
    lists:reverse(Acc);
run_reps(Fun, Reps, Acc) ->
    case catch Fun() of
        error -> run_reps(Fun, Reps - 1, Acc);
        {'EXIT', _} -> run_reps(Fun, Reps - 1, Acc);
        Res -> run_reps(Fun, Reps - 1, [Res | Acc])
    end.

