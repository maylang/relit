
(* 
 * 
 * *)

let ppx_name = "relit"

open Ast_mapper
open Parsetree
open Typedtree
open Asttypes

module Location = Ppxlib.Location

open Call_record

let fully_expanded structure =
  let exception HasRelitCall in
  let open Parsetree in
  let open Longident in
  let expr_mapper mapper e = match e.pexp_desc with
    | Pexp_apply (
        {pexp_desc = Pexp_ident {txt = Lident "raise"; _}},
        [(_, {pexp_attributes = ({txt = "relit"}, _) :: _;
              pexp_desc = Pexp_construct ({txt = Ldot (_, "Call"); _},
              Some {pexp_desc = Pexp_tuple [_ ;
                {pexp_desc = Pexp_constant (Pconst_string _); _}]; _} )})]
      ) ->
        raise HasRelitCall
    | _ -> Ast_mapper.default_mapper.expr mapper e
  in
  let mapper = { Ast_mapper.default_mapper with expr = expr_mapper } in
  match mapper.structure mapper structure with
  | _ -> true
  | exception HasRelitCall -> false

let map_structure f call_records structure =
  let open Parsetree in
  let expr_mapper mapper expr =

    (* If we've matched and typed this location
     * in the previous run, replace it *)
    match Locmap.find expr.pexp_loc call_records with
    | call_record ->
      begin match f call_record with
        | a -> a
        | exception Location.Error loc_error ->
            let extension = Location.Error.to_extension loc_error in
            Ast_helper.Exp.extension ~loc:expr.pexp_loc extension
      end
    | exception Not_found ->
        (* continue down that expression *)
        Ast_mapper.default_mapper.expr mapper expr
  in
  let mapper = { Ast_mapper.default_mapper with expr = expr_mapper } in
  mapper.structure mapper structure

(* Overarching view of what's happening.
 * Reading this is crucial. *)
let relit_expansion_pass structure =
  let call_records = Extract_call_records.from structure in
  let for_each call_record =
    let proto_expansion = Expansion.expand_call call_record in
    let proto_expansion = Hygiene.check call_record proto_expansion in

    (* We ensure capture avoidance by replacing each splice reference
     * with a fresh variable... *)
    let (splices, open_expansion) =
      Splice.take_splices_out proto_expansion in
    Splice.validate_splices splices (String.length call_record.body);
    let spliced_asts =
      Splice.run_reason_parser_against splices call_record.body in

    (* ... and then wrap the body in a function that is immediately applied
     * to these splices. *)
    Splice.fill_in_splices
      ~body_of_lambda:open_expansion
      ~spliced_asts
      ~loc:call_record.loc
      ~path:call_record.path
  in map_structure for_each call_records structure

let rec relit_mapper =
  let rec structure_mapping structure =
    if fully_expanded structure then structure
    else
      let structure = relit_expansion_pass structure in
      structure_mapping structure
  in
  { default_mapper with
    structure = (fun _ -> structure_mapping) }

let () =
  register ppx_name (fun _cookies -> relit_mapper)
