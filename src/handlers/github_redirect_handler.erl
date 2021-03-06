-module(github_redirect_handler).

%%% HTTP handler that redirects the user to the OAuth endpoint of GitHub
%%% with the client_id that identifies this application

-export([init/3,
         handle/2,
         terminate/3]).

init(_Type, Req, []) ->
  {ok, Req, no_state}.

handle(Req, State) ->
  case os:getenv("GITHUB_CLIENTID", false) of
    false ->
      lager:error(<<"Github credentials not found in environment">>);
    GithubClientId ->
      GithubUrl = [<<"http://github.com/login/oauth/authorize">>,
                   <<"?scope=user:email&client_id=">>, GithubClientId],
      {ok, Req2} = cowboy_req:reply(303, [{<<"location">>, GithubUrl}], Req),
      {ok, Req2, State}
  end.

terminate(_Reason, _Req, _State) ->
  ok.
