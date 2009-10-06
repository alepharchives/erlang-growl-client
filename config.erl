-module(config).
-compile(export_all).

read(FileName) ->
	Cfg = file:consult(FileName),
	Cfg.


get(_Key, []) ->
  {error, not_found};
get(Key, [{Key, Value} | _Config]) ->
  {ok, Value};
get(Key, [{_Other, _Value} | Config]) ->
  get(Key, Config).

	
