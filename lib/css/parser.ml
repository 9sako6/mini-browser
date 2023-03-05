open Node

exception Invalid_declaration
exception Unknown_selector
exception Invalid_size_value of string

let build_value tokens =
  let build_px_size_value token =
    let number_regexp = Str.regexp "[0-9-]+" in
    let size =
      if Str.string_match number_regexp token 0 then
        Str.matched_string token |> float_of_string
      else Invalid_size_value token |> raise
    in
    Size (size, Px)
  in

  let first_token = List.hd tokens in
  let px_size_regexp = Str.regexp "[0-9-]+px" in
  if Str.string_match px_size_regexp first_token 0 then
    build_px_size_value first_token
  else Keyword (String.concat "" tokens)

let parse_declaration tokens =
  match tokens with
  | name :: ":" :: rest ->
      let rec parse_declaration_value value_tokens rest =
        match rest with
        | ";" :: rest -> (value_tokens, rest)
        | head :: rest -> parse_declaration_value (value_tokens @ [ head ]) rest
        | [] -> (value_tokens, [])
      in
      let value_tokens, rest = parse_declaration_value [] rest in
      (Declaration (name, build_value value_tokens), rest)
  | _ -> raise Invalid_declaration

let%expect_test "parse_declaration" =
  let declaration, rest =
    parse_declaration
      [ "display"; ":"; "inline"; ";"; "}"; "."; "foo"; "{"; "}" ]
  in
  print_endline (string_of_declaration declaration);
  assert (rest = [ "}"; "."; "foo"; "{"; "}" ]);
  [%expect {| Declaration(display: inline) |}]

let%expect_test "parse_declaration" =
  let declaration, rest =
    parse_declaration [ "margin"; ":"; "10px"; ";"; "}"; "."; "foo"; "{"; "}" ]
  in
  print_endline (string_of_declaration declaration);
  assert (rest = [ "}"; "."; "foo"; "{"; "}" ]);
  [%expect {| Declaration(margin: 10. px) |}]

let%expect_test "parse_declaration" =
  let declaration, rest =
    parse_declaration
      [ "color"; ":"; "#"; "191919"; ";"; "}"; "."; "foo"; "{"; "}" ]
  in
  print_endline (string_of_declaration declaration);
  assert (rest = [ "}"; "."; "foo"; "{"; "}" ]);
  [%expect {| Declaration(color: #191919) |}]

let parse_declarations tokens =
  let rec acc declarations rest =
    match rest with
    | "{" :: rest -> acc declarations rest
    | "}" :: _ -> (declarations, rest)
    | _ ->
        let declaration, rest = parse_declaration rest in
        acc (declarations @ [ declaration ]) rest
  in
  acc [] tokens

let%expect_test "parse_declarations" =
  let declarations, rest =
    "display: none; color: #191919; font-size: 14px;}" |> Tokenizer.tokenize
    |> parse_declarations
  in
  assert (rest = [ "}" ]);
  declarations |> List.map string_of_declaration |> List.iter print_endline;
  [%expect
    {|
    Declaration(display: none)
    Declaration(color: #191919)
    Declaration(font-size: 14. px)
  |}]

let parse_selector tokens =
  let rec split selector_tokens rest =
    match rest with
    | [] -> (selector_tokens, [])
    | "{" :: _ -> (selector_tokens, rest)
    | "," :: rest -> (selector_tokens, rest)
    | head :: rest -> split (selector_tokens @ [ head ]) rest
  in
  let selector_tokens, rest = split [] tokens in
  let selector =
    match selector_tokens with
    | "*" :: _ -> Universal_selector
    | "." :: t -> Class_selector (String.concat "" t)
    | _ -> raise Unknown_selector
  in
  (selector, rest)

let%expect_test "parse_selector" =
  let selector, _ =
    "* {font-size: 14px;}" |> Tokenizer.tokenize |> parse_selector
  in
  selector |> string_of_selector |> print_endline;
  [%expect {| Universal_selector |}]

let%expect_test "parse_selector" =
  let selector, _ =
    ".alert {color: red;}" |> Tokenizer.tokenize |> parse_selector
  in
  selector |> string_of_selector |> print_endline;
  [%expect {| Class_selector(alert) |}]

let parse_comma_separated_selectors tokens =
  let rec acc selectors rest =
    match rest with
    | "{" :: _ -> (selectors, rest)
    | _ ->
        let selector, rest = parse_selector rest in
        acc (selectors @ [ selector ]) rest
  in
  let selectors, rest = acc [] tokens in
  (selectors, rest)

let parse_rule tokens =
  let rec split rule_tokens rest =
    match rest with
    | [] -> (rule_tokens, [])
    | "}" :: rest -> (rule_tokens @ [ "}" ], rest)
    | head :: rest -> split (rule_tokens @ [ head ]) rest
  in
  let rule_tokens, rule_rest = split [] tokens in
  let selectors, rest = parse_comma_separated_selectors rule_tokens in
  let declarations, _ = parse_declarations rest in
  (Rule (selectors, declarations), rule_rest)

let parse_rules tokens =
  let rec acc rules rest =
    match rest with
    | [] -> (rules, [])
    | _ ->
        let rule, rest = parse_rule rest in
        acc (rules @ [ rule ]) rest
  in
  acc [] tokens

let parse tokens =
  let rules, _ = parse_rules tokens in
  Stylesheet rules

let%expect_test "parse" =
  ".foo,.bar {\n  display: flex;\n  color: red;\n}\n" |> Tokenizer.tokenize
  |> parse |> string_of_stylesheet |> print_endline;
  [%expect
    {| Stylesheet([Rule([Class_selector(foo); Class_selector(bar)], [Declaration(display: flex); Declaration(color: red)])]) |}]
