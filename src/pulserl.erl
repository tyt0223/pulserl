%%%-------------------------------------------------------------------
%%% @author Alpha Umaru Shaw <shawalpha5@gmail.com>
%%% @doc
%%%
%%% @end
%%% Copyright: (C) 2020, Skulup Ltd
%%%-------------------------------------------------------------------

-module(pulserl).

-include("pulserl.hrl").

%% API
-export([await/1, await/2]).

-export([start_client/1, start_client/2]).

-export([start_consumer/2, start_consumer/3]).

-export([start_producer/1, start_producer/2]).

-export([produce/2, produce/3, produce/4,
	 sync_produce/2, sync_produce/3]).

-export([ack/1, ack/2, c_ack/1, c_ack/2, consume/2,
	 nack/1, nack/2]).

-export([ack_cumulative/1, ack_cumulative/2,
	 negative_ack/1, negative_ack/2]).

%% Expose for demo purposes
-export([start_consumption_in_background/2]).

%%--------------------------------------------------------------
%% @doc Starts the pulserl client.
%% -------------------------------------------------------------
start_client(ServiceUrl) ->
    start_client(ServiceUrl, #clientConfig{}).

%%--------------------------------------------------------------
%% @doc Starts the pulserl client
%% -------------------------------------------------------------
-spec start_client(ServiceUrl :: string() |
				 binary()) -> ok | {error, term()}.

start_client(ServiceUrl, ClientConfig) ->
    pulserl_client_sup:start_client(ServiceUrl,
				    ClientConfig).

%%--------------------------------------------------------------
%% @doc Starts a consumer using the specified topic
%% and default options
%% -------------------------------------------------------------
start_consumer(Topic, Subscription) ->
    Options = pulserl_app:def_consumer_options(),
    start_consumer(Topic, Subscription, Options).

%%-----------------------------------------------------------------
%% @doc Starts a consumer using the specified topic and options
%% ----------------------------------------------------------------
-spec start_consumer(Topic :: topic(),
		     Options :: options()) -> {ok, pid()} | {error, term()}.

start_consumer(Topic, Subscription, Options) ->
    Topic2 = topic_utils:parse(Topic),
    pulserl_consumer:create(Topic2, Subscription, Options).

%%--------------------------------------------------------------
%% @doc Starts a producer using the specified topic
%% and default options
%% -------------------------------------------------------------
start_producer(Topic) ->
    Options = pulserl_app:def_producer_options(),
    start_producer(Topic, Options).

%%-----------------------------------------------------------------
%% @doc Starts a producer using the specified topic and options
%% ----------------------------------------------------------------
-spec start_producer(Topic :: topic(),
		     Options :: options()) -> {ok, pid()} | {error, term()}.

start_producer(Topic, Options) ->
    Topic2 = topic_utils:parse(Topic),
    pulserl_producer:create(Topic2, Options).

%%--------------------------------------------------------------------
%% @doc publish a message asynchronously
%%--------------------------------------------------------------------
% produce(PidOrTopic, Payload, Options) when not is_record(Payload, producerMessage) ->
%     produce(PidOrTopic, pulserl_producer:new_message(Payload, Options), ?UNDEF);
produce(PidOrTopic, Payload)
    when is_list(Payload) or is_binary(Payload) ->
    produce(PidOrTopic, Payload, []);
produce(PidOrTopic, #producerMessage{} = Msg) ->
    produce(PidOrTopic, Msg, ?UNDEF).

%%-------------------------------------------------------------------------------
%% @doc publish a message asynchronously to the specified topic or producer
%% If `PidOrTopic` is a topic, a registry lookup is done to fine an already existing
%% producer created for the specified topic; if none is found, one is created and
%% register for future calls
%%-------------------------------------------------------------------------------
produce(PidOrTopic, #producerMessage{} = Msg, Callback)
    when is_function(Callback) orelse
	   Callback == (?UNDEF) ->
    if is_pid(PidOrTopic) ->
	   pulserl_producer:send(PidOrTopic, Msg, Callback);
       true ->
	   case pulserl_instance_registry:get_producer(PidOrTopic,
        pulserl_app:def_producer_options())
	       of
	     {ok, Pid} -> produce(Pid, Msg, Callback);
	     Other -> Other
	   end
    end;
%%--------------------------------------------------------------------
%% @doc publish a message asynchronously
%%--------------------------------------------------------------------
% produce(PidOrTopic, Payload, Options) when not is_record(Payload, producerMessage) ->
%     produce(PidOrTopic, pulserl_producer:new_message(Payload, Options), ?UNDEF);
produce(PidOrTopic, Payload, Options)
    when is_list(Payload) or is_binary(Payload) andalso
	   is_list(Options) ->
    Callback = proplists:get_value(callback, Options,
				   ?UNDEF),
    Options2 = proplists:delete(callback, Options),
    produce(PidOrTopic, Payload, Options2, Callback).

%%--------------------------------------------------------------------
%% @doc publish a message asynchronously
%%--------------------------------------------------------------------
produce(PidOrTopic, Payload, Options, Callback)
    when is_list(Payload) or is_binary(Payload) andalso
	   is_list(Options) andalso
	     (is_function(Callback) orelse Callback == (?UNDEF)) ->
    produce(PidOrTopic,
	    pulserl_producer:new_message(Payload, Options),
	    Callback).

%%--------------------------------------------------------------------
%% @doc publish a message synchronously
%%--------------------------------------------------------------------
sync_produce(PidOrTopic, Payload)
    when is_list(Payload) orelse is_binary(Payload) ->
    sync_produce(PidOrTopic,
		 pulserl_producer:new_message(Payload, []), ?UNDEF);
%%--------------------------------------------------------------------
%% @doc publish a message synchronously
%%--------------------------------------------------------------------
sync_produce(Pid, #producerMessage{} = Msg) ->
    sync_produce(Pid, Msg, ?UNDEF).

%%--------------------------------------------------------------------
%% @doc publish a message synchronously
%%--------------------------------------------------------------------
sync_produce(PidOrTopic,  Payload, Options)
    when (is_list(Payload) or is_binary(Payload)) andalso is_list(Options) ->
    sync_produce(PidOrTopic,
		 pulserl_producer:new_message( Payload, Options));
%%-------------------------------------------------------------------------------
%% @doc publish a message synchronously to the specified topic or producer
%% If `PidOrTopic` is a topic, a registry lookup is done to fine an already existing
%% producer created for the specified topic; if none is found, one is created and
%% register for future calls
%%-------------------------------------------------------------------------------
sync_produce(PidOrTopic, #producerMessage{} = Msg,
	     Timeout)
    when is_integer(Timeout) orelse Timeout == (?UNDEF) ->
    if is_pid(PidOrTopic) ->
	   pulserl_producer:sync_send(PidOrTopic, Msg, Timeout);
       true ->
	   case pulserl_instance_registry:get_producer(PidOrTopic,
        pulserl_app:def_producer_options())
	       of
	     {ok, Pid} -> sync_produce(Pid, Msg, Timeout);
	     Other -> Other
	   end
    end.

%%-------------------------------------------------------------------------------
%% @doc consume a message from the consumer of the specified topic.
%% If `PidOrTopic` is a topic, a registry lookup is done to fine an already existing
%% consumer created for the specified topic; if none is found, one is created and
%% register for future calls
%%-------------------------------------------------------------------------------
consume(PidOrTopic, Subscription) ->
    if is_pid(PidOrTopic) ->
	   pulserl_consumer:receive_message(PidOrTopic);
       true ->
	   case pulserl_instance_registry:get_consumer(PidOrTopic,
						       Subscription, [])
	       of
	     {ok, Pid} -> consume(Pid, Subscription);
	     Other -> Other
	   end
    end.

ack(#consumerMessage{consumer = Pid, id = Id}) ->
    pulserl:ack(Pid, Id).

ack(Pid, #messageId{} = Id) when is_pid(Pid) ->
    pulserl_consumer:ack(Pid, Id, false).

c_ack(#consumerMessage{consumer = Pid, id = Id}) ->
    pulserl:c_ack(Pid, Id).

c_ack(Pid, #messageId{} = Id) when is_pid(Pid) ->
    pulserl_consumer:ack(Pid, Id, true).

nack(#consumerMessage{consumer = Pid, id = Id}) ->
    pulserl:negative_ack(Pid, Id).

nack(Pid, #messageId{} = Id) when is_pid(Pid) ->
    pulserl_consumer:nack(Pid, Id).

%% @deprecated
ack_cumulative(#consumerMessage{consumer = Pid,
				id = Id}) ->
    pulserl:ack_cumulative(Pid, Id).

%% @deprecated
ack_cumulative(Pid, #messageId{} = Id)
    when is_pid(Pid) ->
    pulserl_consumer:ack(Pid, Id, true).

%% @deprecated
negative_ack(#consumerMessage{consumer = Pid,
			      id = Id}) ->
    pulserl:negative_ack(Pid, Id).

%% @deprecated
negative_ack(Pid, #messageId{} = Id) when is_pid(Pid) ->
    pulserl_consumer:negative_ack(Pid, Id).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
await(Tag) -> await(Tag, 10000).

%%--------------------------------------------------------------------
%% @doc
%% @end
%%--------------------------------------------------------------------
await(Tag, Timeout) ->
    receive
      {Tag, Reply} -> Reply after Timeout -> {error, timeout}
    end.

%%% public only for demo purpose
start_consumption_in_background(TopicOrPid,
				Subscription) ->
    spawn(fun () -> do_consume(TopicOrPid, Subscription)
	  end).

do_consume(PidOrTopic, Subscription) ->
    case consume(PidOrTopic, Subscription) of
      #consumerMessage{id = Id, payload = Payload} =
	  ConsumedMsg ->
	  _ = ack(ConsumedMsg),
	  io:format("Consumer Received: ~p. Id(~p)~n",
		    [Payload, Id]);
      ?ERROR_CLIENT_NOT_STARTED ->
	  error(?ERROR_CLIENT_NOT_STARTED);
      {error, Reason} ->
	  error_logger:error_msg("Consumer Error. Reason = ~p",
				 [Reason]);
      false -> timer:sleep(10), ok
    end,
    do_consume(PidOrTopic, Subscription).
