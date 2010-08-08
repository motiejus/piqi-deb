(*
   Copyright 2009, 2010 Anton Lavrik

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.

The JSON generator implementation is based on Martin Jambon's "yojson" library.
The original code was taken from here:
  http://martin.jambon.free.fr/yojson.html

Below is the original copyright notice and the license:

Copyright (c) 2010 Martin Jambon
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:
1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.
3. The name of the author may not be used to endorse or promote products
   derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*)

open Piqi_json_common

let hex n =
  Char.chr (
    if n < 10 then n + 48
    else n + 87
  )

let write_special src start stop ob str =
  Buffer.add_substring ob src !start (stop - !start);
  Buffer.add_string ob str;
  start := stop + 1

let write_control_char src start stop ob c =
  Buffer.add_substring ob src !start (stop - !start);
  Buffer.add_string ob "\\u00";
  Buffer.add_char ob (hex (Char.code c lsr 4));
  Buffer.add_char ob (hex (Char.code c land 0xf));
  start := stop + 1

let finish_string src start ob =
  try
    Buffer.add_substring ob src !start (String.length src - !start)
  with _ ->
    Printf.eprintf "src=%S start=%i len=%i\n%!"
      src !start (String.length src - !start);
    failwith "oops"

let write_string_body ob s =
  let start = ref 0 in
  for i = 0 to String.length s - 1 do
    match s.[i] with
	'"' -> write_special s start i ob "\\\""
      | '\\' -> write_special s start i ob "\\\\"
      | '\b' -> write_special s start i ob "\\b"
      | '\012' -> write_special s start i ob "\\f"
      | '\n' -> write_special s start i ob "\\n"
      | '\r' -> write_special s start i ob "\\r"
      | '\t' -> write_special s start i ob "\\t"
      | '\x00'..'\x1F'
      | '\x7F' as c -> write_control_char s start i ob c
      | _ -> ()
  done;
  finish_string s start ob

let write_string ob s =
  Buffer.add_char ob '"';
  write_string_body ob s;
  Buffer.add_char ob '"'

let json_string_of_string s =
  let ob = Buffer.create 10 in
  write_string ob s;
  Buffer.contents ob

let test_string () =
  let s = String.create 256 in
  for i = 0 to 255 do
    s.[i] <- Char.chr i
  done;
  json_string_of_string s


let write_null ob () =
  Buffer.add_string ob "null"

let write_bool ob x =
  Buffer.add_string ob (if x then "true" else "false")


let write_int ob x =
  Buffer.add_string ob (string_of_int x)


(*
  Ensure that the float is not printed as an int.
  This is not required by JSON, but useful in order to guarantee
  reversibility.
*)
let float_needs_period s =
  try
    for i = 0 to String.length s - 1 do
      match s.[i] with
	  '0'..'9' | '-' -> ()
	| _ -> raise Exit
    done;
    true
  with Exit ->
    false

(*
  Both write_float_fast and write_float guarantee
  that a sufficient number of digits are printed in order to 
  allow reversibility.

  The _fast version is faster but often produces unnecessarily long numbers.
*)
let write_float_fast ob x =
  let s = Printf.sprintf "%.17g" x in
  Buffer.add_string ob s;
  if float_needs_period s then
    Buffer.add_string ob ".0"


let write_float ob x =
  let s1 = Printf.sprintf "%.16g" x in
  let s =
    if float_of_string s1 = x then s1
    else Printf.sprintf "%.17g" x
  in
  Buffer.add_string ob s;
  if float_needs_period s then
    Buffer.add_string ob ".0"


let write_float ob x =
  (* Using JavaScript notation for NaN and Infinity *)
  match classify_float x with
    FP_nan ->
      Buffer.add_string ob "\"NaN\""
  | FP_infinite ->
      Buffer.add_string ob (if x > 0. then "\"Infinity\"" else "\"-Infinity\"")
  | _ ->
      write_float ob x
      (*
      write_float_fast ob x
      *)


let json_string_of_float x =
  let ob = Buffer.create 20 in
  write_float ob x;
  Buffer.contents ob


let test_float () =
  let l = [ 0.; 1.; -1. ] in
  let l = l @ List.map (fun x -> 2. *. x +. 1.) l in
  let l = l @ List.map (fun x -> x /. sqrt 2.) l in
  let l = l @ List.map (fun x -> x *. sqrt 3.) l in
  let l = l @ List.map cos l in
  let l = l @ List.map (fun x -> x *. 1.23e50) l in
  let l = l @ [ infinity; neg_infinity ] in
  List.iter (
    fun x -> 
      let s = Printf.sprintf "%.17g" x in
      let y = float_of_string s in
      Printf.printf "%g %g %S %B\n" x y s (x = y)
  )
    l

(*
let () = test_float ()
*)


let uint64_to_string x =
  Printf.sprintf "%Lu" x


let rec iter2_aux f_elt f_sep x = function
    [] -> ()
  | y :: l ->
      f_sep x;
      f_elt x y;
      iter2_aux f_elt f_sep x l

let iter2 f_elt f_sep x = function
    [] -> ()
  | y :: l ->
      f_elt x y;
      iter2_aux f_elt f_sep x l

let f_sep ob =
  Buffer.add_char ob ','

let rec write_json ob (x : json) =
  match x with
      `Null () -> write_null ob ()
    | `Bool b -> write_bool ob b
    | `Int i -> Buffer.add_string ob (Int64.to_string i)
    | `Uint i -> Buffer.add_string ob (uint64_to_string i)
    | `Intlit s -> Buffer.add_string ob s
    | `Float f -> write_float ob f
    | `Floatlit s -> Buffer.add_string ob s
    | `String s -> write_string ob s
    | `Stringlit s -> Buffer.add_string ob s
    | `Assoc l -> write_assoc ob l
    | `List l -> write_list ob l

and write_assoc ob l =
  let f_elt ob (s, x) =
    write_string ob s;
    Buffer.add_char ob ':';
    write_json ob x
  in
  Buffer.add_char ob '{';
  iter2 f_elt f_sep ob l;
  Buffer.add_char ob '}';

and write_list ob l =
  Buffer.add_char ob '[';
  iter2 write_json f_sep ob l;
  Buffer.add_char ob ']'


let to_outbuf ?(std = false) ob x =
  write_json ob x


let to_string ?buf ?(len = 256) ?std x =
  let ob =
    match buf with
	None -> Buffer.create len
      | Some ob ->
	  Buffer.clear ob;
	  ob
  in
  to_outbuf ?std ob x;
  let s = Buffer.contents ob in
  Buffer.clear ob;
  s

let to_channel ?buf ?len ?std oc x =
  let ob =
    match buf with
	None -> Buffer.create 100
      | Some ob -> ob
  in
  to_outbuf ?std ob x;
  Buffer.output_buffer oc ob 
  

(*
 * Pretty-printed JSON
 *)

open Printf
open Easy_format
  
let array = list
let record = list
let tuple = { list with
		space_after_opening = false;
		space_before_closing = false;
		align_closing = false }
let variant = { list with
		  space_before_closing = false; }

let rec format (x : json) =
  match x with
      `Null () -> Atom ("null", atom)
    | `Bool x -> Atom ((if x then "true" else "false"), atom)
    | `Int i -> Atom (Int64.to_string i, atom)
    | `Uint i -> Atom (uint64_to_string i, atom)
    | `Float x ->
	let s = json_string_of_float x in
	Atom (s, atom)
    | `String s -> Atom (json_string_of_string s, atom)
    | `Intlit s
    | `Floatlit s
    | `Stringlit s -> Atom (s, atom)
    | `List [] -> Atom ("[]", atom)
    | `List l -> List (("[", ",", "]", array), List.map format l)
    | `Assoc [] -> Atom ("{}", atom)
    | `Assoc l -> List (("{", ",", "}", record), List.map format_field l)
	    
and format_field (name, x) =
  let s = sprintf "%s:" (json_string_of_string name) in
  Label ((Atom (s, atom), label), format x)


let pretty_to_string x =
  Easy_format.Pretty.to_string (format x)

let pretty_to_channel oc x =
  Easy_format.Pretty.to_channel oc (format x)

