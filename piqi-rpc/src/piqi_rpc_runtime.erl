%% Copyright 2009, 2010, 2011 Anton Lavrik
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

%%
%% @doc Piqi-RPC runtime support library
%%
%% This is a runtime support library for Piqi-RPC Erlang modules generated by
%% the "piqic-erlang-rpc" command-line tool.
%%

-module(piqi_rpc_runtime).

-compile(export_all).


-include_lib("piqi/include/piqi_rpc_piqi.hrl").


%-define(DEBUG, 1).
-include("debug.hrl").


% TODO: -specs, doc


call(Mod, Name, Input) ->
    ?PRINT({call, Mod, Name, Input}),
    check_function_exported(Mod, Name, 1),
    Mod:Name(Input).


check_function_exported(Mod, Name, Arity) ->
    % NOTE: this function doesn't load the module automatically and returns
    % false if the module is not loaded
    case erlang:function_exported(Mod, Name, Arity) of
        true -> ok;
        false ->
            Error = lists:concat([
                "function ", Mod, ":", Name, "/", Arity, " is not exported"]),
            throw_rpc_error({'internal_error', list_to_binary(Error)})
    end.


get_piqi(BinPiqiList, _OutputFormat = 'pb') ->
    % return the Piqi module and all the dependencies encoded as a list of Piqi
    % each encoded using Protobuf binary format
    piqirun:gen_list('undefined', fun piqirun:binary_to_block/2, BinPiqiList);

get_piqi(BinPiqiList, OutputFormat) -> % piq (i.e. text/plain), json, xml
    L = [ convert_piqi(X, OutputFormat) || X <- BinPiqiList ],
    string:join(L, "\n\n").


convert(RpcMod, TypeName, InputFormat, OutputFormat, Data) ->
    piqi_tools:convert(RpcMod, TypeName, InputFormat, OutputFormat, Data).


convert_piqi(BinPiqi, OutputFormat) ->
    {ok, Bin} = convert(_RpcMod = 'undefined', <<"piqi">>, 'pb', OutputFormat, BinPiqi),
    binary_to_list(Bin).


decode_input(_RpcMod, _Decoder, _TypeName, _InputFormat, 'undefined') ->
    throw_rpc_error('missing_input');

decode_input(RpcMod, Decoder, TypeName, InputFormat, InputData) ->
    BinInput =
        % NOTE: converting anyway even in the input is encoded using 'pb'
        % encoding to check the validity
        case convert(RpcMod, TypeName, InputFormat, 'pb', InputData) of
            {ok, X} -> X;
            {error, Error} ->
                throw_rpc_error({'invalid_input', Error})
        end,
    Decoder(BinInput).


encode_common(RpcMod, Encoder, TypeName, OutputFormat, Output) ->
    IolistOutput =
        try Encoder(Output)
        catch
            Class:Reason ->
                OutputStr = lists:flatten(format_term(Output)),
                Error = io_lib:format(
                    "error encoding output:~n"
                    "~s,~n"
                    "exception: ~w:~P,~n"
                    "stacktrace: ~P",
                    [OutputStr, Class, Reason, 30, erlang:get_stacktrace(), 30]),
                throw_rpc_error(
                    {'invalid_output', iolist_to_binary(Error)})
        end,
    BinOutput = iolist_to_binary(IolistOutput),
    case OutputFormat of
        'pb' -> {ok, BinOutput}; % already in needed format
        _ -> convert(RpcMod, TypeName, 'pb', OutputFormat, BinOutput)
    end.


encode_output(RpcMod, Encoder, TypeName, OutputFormat, Output) ->
    case encode_common(RpcMod, Encoder, TypeName, OutputFormat, Output) of
        {ok, OutputData} -> {ok, OutputData};
        {error, Error} ->
            throw_rpc_error(
                {'invalid_output', "error converting output: " ++ Error})
    end.


encode_error(RpcMod, Encoder, TypeName, OutputFormat, Output) ->
    case encode_common(RpcMod, Encoder, TypeName, OutputFormat, Output) of
        {ok, ErrorData} -> {error, ErrorData};
        {error, Error} ->
            throw_rpc_error(
                {'invalid_output', "error converting error: " ++ Error})
    end.


-spec throw_rpc_error/1 :: (Error :: piqi_rpc_rpc_error()) -> no_return().
throw_rpc_error(Error) ->
    throw({'rpc_error', Error}).


%
% Error handlers
%

check_empty_input('undefined') -> ok;
check_empty_input(_) ->
    throw_rpc_error({'invalid_input', "empty input expected"}).


-spec handle_unknown_function/0 :: () -> no_return().

handle_unknown_function() ->
    throw_rpc_error('unknown_function').


-spec handle_invalid_result/2 :: (
    Name :: binary(),
    Result :: any()) -> no_return().

handle_invalid_result(Name, Result) ->
    ResultIolist = format_term(Result),
    Error = ["function ", Name, " returned invalid result:\n", ResultIolist],
    throw_rpc_error({'internal_error', iolist_to_binary(Error)}).


% already got the error formatted properly by one of the above handlers
handle_runtime_exception(throw, {'rpc_error', _} = X) -> X;
handle_runtime_exception(Class, Reason) ->
    Error = io_lib:format(
        "exception: ~w:~P,~n"
        "stacktrace: ~P",
        [Class, Reason, 30, erlang:get_stacktrace(), 30]),
    {'rpc_error', {'internal_error', iolist_to_binary(Error)}}.


% Convert Erlang term to a human-readable string
format_term(Term) ->
    % hardcoding the maximum length of the output string
    format_term(Term, _MaxLen = 8192).


-spec format_term/2 :: (
    Term :: term(),
    MaxLen :: pos_integer()) -> iolist().

% Convert Erlang term to a human-readable string. If `trunc_io` module is
% present in the system and loaded, the string is truncated according to the
% `MaxLen` argument.
format_term(Term, MaxLen) ->
    case erlang:function_exported(trunc_io, print, 2) and
        % NOTE: flat_size returns the size of a term in words, but we don't care
        % here and just compare it with the maximum string length
        (erts_debug:flat_size(Term) > MaxLen) of

        true ->
            {Res, _} = trunc_io:print(Term, MaxLen),
            Res;

        false ->
            % fall back to stdlib if the term is small or if "trunc_io" module
            % is missing
            io_lib:format("~p", [Term])
    end.

