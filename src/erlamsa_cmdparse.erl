% Copyright (c) 2011-2014 Aki Helin
% Copyright (c) 2014-2015 Alexander Bolshev aka dark_k3y
%
% Permission is hereby granted, free of charge, to any person obtaining a copy
% of this software and associated documentation files (the "Software"), to deal
% in the Software without restriction, including without limitation the rights
% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
% copies of the Software, and to permit persons to whom the Software is
% furnished to do so, subject to the following conditions:
%
% The above copyright notice and this permission notice shall be included in
% all copies or substantial portions of the Software.
%
% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT
% SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
% DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
% OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
% THE USE OR OTHER DEALINGS IN THE SOFTWARE.
%
%%%-------------------------------------------------------------------
%%% @author dark_k3y
%%% @doc
%%% Cmd args parser.
%%% @end
%%%-------------------------------------------------------------------

-module(erlamsa_cmdparse).

-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").
-compile([export_all]).
-endif.

-include("erlamsa.hrl").

% API
-export([parse/1, usage/0]).

cmdline_optsspec() ->
	[{help		, $h, 	"help", 		undefined, 				"show this thing"},
%	 {about		, $a, 	"about", 		undefined, 				"what is this thing"},
%	 {version	, $V, 	"version",		undefined, 				"show program version"},
	 {input		, $i, 	"input",		string, 				"<arg>, special input, e.g. lport:rhost:rport (fuzzing proxy) or :port, host:port for data input from net"},
	 {proxyprob	, $P,	"proxyprob",	{string, "0.0,0.0"},	"<arg>, fuzzing probability for proxy mode s->c,c->s"},
%	 {output	, $o, 	"output",		{string, "-"}, 			"<arg>, output pattern, e.g. /tmp/fuzz-%n.foo, -, :80 or 127.0.0.1:80 [-]"},
	 {count		, $n, 	"count",		{integer, 1},			"<arg>, how many outputs to generate (number or inf)"},
	 {seed		, $s, 	"seed",			string, 				"<arg>, random seed {int,int,int}"},
	 {mutations , $m,   "mutations",	{string, 
	  					 	erlamsa_mutations:default_string()},"<arg>, which mutations to use"},
	 % {patterns	, $p,	"patterns",		{string, "od,nd,bu"},	"<arg>, which mutation patterns to use"},
	 % {generators, $g,	"generators",	{string, ""},			"<arg>, which data generators to use"},
	 % {meta		, $M, 	"meta",			{string, ""},			"<arg>, save metadata about fuzzing process to this file"},
	 {logger	, $L,	"logger",		string,					"<arg>, which logger to use, e.g. file=filename"},
	 {workers	, $w, 	"workers",		{integer, 10},			"<arg>, number of workers in server mode"},
%	 {recursive , $r,	"recursive",	undefined, 				"include files in subdirectories"},
	 {doverbose	, $v,	"verbose",		undefined,				"show progress during generation"},
	 {list		, $l,	"list",			undefined,				"list mutations, patterns and generators"}].

usage() ->
	getopt:usage(cmdline_optsspec(), "erlamsa", "[file ...]").

fail(Reason) ->
	io:format("~s~n", [Reason]),
	usage(),
	halt(-1).

parse_logger_opts(LogOpts, Dict) ->
	case string:tokens(LogOpts, "=") of
		["file", FName] -> 
			maps:put(logger_file, FName,
				maps:put(logger_type, logger_file, Dict));
		_Else -> fail(io_lib:format("invalid logger specification: '~s'", [LogOpts]))
	end.

parse_proxyprob_opts(ProxyProbOpts, Dict) ->
	case string:tokens(ProxyProbOpts, ",") of
		[SC, CS] -> 
			maps:put(proxy_probs, {list_to_float(SC), list_to_float(CS)}, Dict);
		_Else -> fail(io_lib:format("invalid proxy fuzzing probability specification: '~s'", [ProxyProbOpts]))
	end.

parse_input_opts(InputOpts, Dict) ->
	case string:tokens(InputOpts, ":") of
		[LPort, RHost, RPort] -> 
			maps:put(proxy_address, {list_to_integer(LPort), RHost, list_to_integer(RPort)}, 
				maps:put(mode, proxy, Dict));
		_Else -> fail(io_lib:format("invalid input specification: '~s'", [InputOpts]))
	end.

parse_mutas_list(Mutators, Dict) ->
	case erlamsa_mutations:string_to_mutators(Mutators) of
		{ok, Ml} ->			
			maps:put(mutations, Ml, Dict);
		{fail, Reason} ->
			fail(Reason)
	end.

%% TODO: seed
parse_seed_opt(Seed, Dict) ->
	maps:puts(seed, list_to_tuple(Seed), Dict).
	
parse(Args) -> 
	case getopt:parse(cmdline_optsspec(), Args) of
		{ok, {Opts, Files}} -> parse_tokens(Opts, Files);
		_Else -> usage(), halt(-1)
	end.

parse_tokens(Opts, []) ->
	parse_opts(Opts, maps:put(paths, ["-"], maps:new()));
parse_tokens(Opts, Paths) ->
	parse_opts(Opts, maps:put(paths, Paths, maps:new())).

parse_opts([help|_T], _Dict) ->
	usage(),
	halt(0);
parse_opts([list|_T], _Dict) ->
	Ms = lists:foldl(
			fun({_,_,_,N,D}, Acc) ->
				[io_lib:format("    ~-3s: ~s~n",[atom_to_list(N),D])|Acc]
			end
		,[],
		lists:sort(fun ({_,_,_,N1,_}, {_,_,_,N2,_}) -> N1 >= N2 end, 
			erlamsa_mutations:mutations())),
	io:format("Mutations (-m)~n~s", [Ms]),
	halt(0);
parse_opts([doverbose|T], Dict) -> 	
	parse_opts(T, maps:put(verbose, 1, Dict));
parse_opts([recursive|T], Dict) -> 
	parse_opts(T, maps:put(recursive, 1, Dict));
parse_opts([{count, N}|T], Dict) -> 
	parse_opts(T, maps:put(n, N, Dict));
parse_opts([{workers, W}|T], Dict) -> 
	parse_opts(T, maps:put(workers, W, Dict));
parse_opts([{meta, FName}|T], Dict) -> 
	parse_opts(T, maps:put(metadata, FName, Dict));
parse_opts([{logger, LogOpts}|T], Dict) -> 
	parse_opts(T, parse_logger_opts(LogOpts, Dict));
parse_opts([{proxyprob, ProxyProbOpts}|T], Dict) -> 
	parse_opts(T, parse_proxyprob_opts(ProxyProbOpts, Dict));
parse_opts([{input, InputOpts}|T], Dict) -> 
	parse_opts(T, parse_input_opts(InputOpts, Dict));
parse_opts([{mutations, Mutators}|T], Dict) -> 
	parse_opts(T, parse_mutas_list(Mutators, Dict));
% parse_opts([{output, OutputOpts}|T], Dict) -> 
% 	parse_opts(T, parse_input_opts(OutputOpts, Dict));
parse_opts([{seed, SeedOpts}|T], Dict) -> 
	parse_opts(T, parse_seed_opt(SeedOpts, Dict));
parse_opts([_|T], Dict) ->
	parse_opts(T, Dict);
parse_opts([], Dict) ->
	Dict.