-module(remind_router).
-behaviour(gen_server).

%%% This module receives user, channel and holiday data, builds a reminder
%%% and sends it through the channel

-export([start_link/0,

         send/3,
         send_test/3,

         init/1,
         handle_call/3,
         handle_cast/2]).

send(User, Channel, HolidayDate) ->
  {ok, Pid} = supervisor:start_child(remind_router_sup, []),
  Message = build_message(User, HolidayDate),
  gen_server:cast(Pid, {send_reminder, User, Channel, HolidayDate, Message, false}).

send_test(User, Channel, HolidayDate) ->
  Username = maps:get(name, User),
  Message = <<"This is a Holiday Ping test: ", Username/binary, " will be out on holidays.">>,
  {ok, Pid} = supervisor:start_child(remind_router_sup, []),
  gen_server:cast(Pid, {send_reminder, User, Channel, HolidayDate, Message, true}).

start_link() ->
  gen_server:start_link(?MODULE, [], []).

init([]) ->
  {ok, []}.

handle_call(_Request, _From, State) ->
  {noreply, State}.

handle_cast({send_reminder, User, Channel, HolidayDate, Message, IsTest}, State) ->
  #{name := ChannelName, configuration := Config, type := Type} = Channel,
  UserName = maps:get(name, User),
  Email = maps:get(email, User),
  lager:debug("Sending reminders for user ~p and channel ~p",
              [UserName, ChannelName]),

  case check_should_send(Email, Channel) of
    ok ->
      Handler = get_handler(Type),
      case Handler:handle(User, HolidayDate, Config, Message) of
        {ok, SentReminders} -> log_reminders(User, Channel, SentReminders, IsTest);
        Error -> lager:warning(<<"Error sending reminders ~p">>, [Error])
      end;
    already_sent ->
      ok;
    limit_exceeded ->
      lager:warning(<<"User ~p exceeded channel limit for type ~p">>,
                    [UserName, Type])
  end,

  {noreply, State};

handle_cast(Request, State) ->
  lager:warning("Unknown message: ~p", [Request]),
  {noreply, State}.

%%% internal
%% at some point the reminder message will be part of the channel
build_message(#{name := UserName}, {Y, M, D}) ->
  list_to_binary(
    io_lib:format(<<"This is a holiday reminder: ~s will be out on ~2..0B/~2..0B/~B.">>,
                  [UserName, D, M, Y])).

get_handler(slack) -> slack_channel;
get_handler(console) -> console_channel;
get_handler(ets) -> ets_channel;
get_handler(webhook) -> webhook_channel;
get_handler(email) -> email_channel.

check_should_send(Email, #{name := ChannelName, type := ChannelType}) ->
  case is_already_sent(Email, ChannelName) of
    true -> already_sent;
    false -> check_limit(Email, ChannelType)
  end.

is_already_sent(Email, ChannelName) ->
  %% the channels currently return ok if all their reminders were sent, so if
  %% one exists we can safely assume the entire pack was sent.
  case db_reminder:sent_count(Email, ChannelName, erlang:date()) of
    {ok, 0} -> false;
    {ok, _} -> true
  end.

check_limit(Email, Type) ->
  ChannelLimits = hp_config:get(monthly_limits),
  case maps:get(Type, ChannelLimits, undefined) of
    Limit when is_integer(Limit), Limit > 0 ->
      case db_reminder:get_monthly_count(Email, Type) of
        {ok, Count} when Count >= Limit -> limit_exceeded;
        _ -> ok
      end;
    _ -> ok
  end.

log_reminders(#{email := Email}, #{name := ChannelName}, Targets, IsTest) ->
  db_reminder:log(Email, ChannelName, Targets, IsTest).
